# Converts a genmai model (HF GPT-2 checkpoint: config.json, model.safetensors fp32, tokenizer.json) into the Core ML
# model GenmaiCoreMLModel runs on the Neural Engine (see CLAUDE.md "Core ML decoder").
#
#   python genmai_coreml.py <HF model dir> <out dir> [--P 256] [--S 64] [--B 5] [--C 32] [--chunks N]
#       [--residual-scale R] [--score-scale C]
#
# writes <out dir>/genmai.mlpackage (or genmai_0.mlpackage, ... with --chunks), genmai_coreml.json, config.json,
# tokenizer.json, and model-coreml.zip (genmai_coreml.json + the packages: the file a model release carries; the
# input method downloads and extracts it). Needs coremltools 9.0, torch 2.7, safetensors
# (Tools/coreml/requirements.txt), macOS.
#
# One multifunction package with two functions sharing one set of states (per layer, fp16 (H, slots, D)):
# - prefill: C prompt tokens at prompt slots start ..< start + C -> log-probs after each of them.
# - decode: one token for each of B rows -> log-probs; row r's step-t token goes to output slot t * B + r, and
#   each row attends to its ancestors' slots through a mask, so beam reordering copies nothing.
# The decode step writes its slots by blending (state * keep + onehot @ k): a dynamic slice update of a state runs
# on the CPU and splits the Neural Engine graph. Every function must use every state, so prefill reads the output
# states × 0. Linear weights: int8, per channel.
#
# The Neural Engine computes in fp16 (max 65504). genmai-310M exceeds that: its residual stream reaches ~81k and one
# head of layer 1 has attention logits up to ~500k (an attention sink). Two exact reparametrizations keep it in range:
# - --residual-scale R: the residual stream is R × the original (embeddings and the attention / MLP output
#   projections × R, layer norm eps × R²; layer norms are scale-invariant, the head uses the unscaled embeddings);
# - --score-scale C: attention logits are computed / C (folded into the query weights), the row maximum subtracted,
#   then × C: softmax(s) = softmax((s / C - max(s / C)) × C); large negative values become -inf, i.e. weight 0.
# genmai-310M: --residual-scale 0.25 --score-scale 256. genmai-90M (v0.1.2) was converted without them.

import argparse
import json
import math
import os
import shutil
import zipfile

import coremltools as ct
import numpy as np
import torch
import torch.nn.functional as F
from coremltools.optimize.coreml import OpLinearQuantizerConfig, OptimizationConfig, linear_quantize_weights
from safetensors.torch import load_file

FORMAT = "genmai-coreml-1"
# the release file; a format the input method cannot run needs another name
ARCHIVE = "model-coreml.zip"


class Weights:
    def __init__(self, hf_dir, residual_scale=1.0, score_scale=1.0):
        cfg = json.load(open(f"{hf_dir}/config.json"))
        self.L, self.E, self.H = cfg["n_layer"], cfg["n_embd"], cfg["n_head"]
        self.D = self.E // self.H
        self.eps = cfg["layer_norm_epsilon"]
        self.residual_scale, self.score_scale = residual_scale, score_scale
        sd = load_file(f"{hf_dir}/model.safetensors")
        self.sd = {k.removeprefix("transformer."): v.float() for k, v in sd.items()}


class Block(torch.nn.Module):
    def __init__(self, w, i):
        super().__init__()
        sd, p, r = w.sd, f"h.{i}.", w.residual_scale
        eps = w.eps * r * r
        self.ln1 = torch.nn.LayerNorm(w.E, eps=eps)
        self.ln1.weight.data, self.ln1.bias.data = sd[p + "ln_1.weight"], sd[p + "ln_1.bias"]
        self.ln2 = torch.nn.LayerNorm(w.E, eps=eps)
        self.ln2.weight.data, self.ln2.bias.data = sd[p + "ln_2.weight"], sd[p + "ln_2.bias"]

        def lin(name, scale=1.0):
            l = torch.nn.Linear(*sd[p + name + ".weight"].shape)
            l.weight.data = sd[p + name + ".weight"].t().contiguous() * scale  # Conv1D (in, out) -> (out, in)
            l.bias.data = sd[p + name + ".bias"] * scale
            return l

        self.qkv, self.proj = lin("attn.c_attn"), lin("attn.c_proj", r)
        self.fc, self.mproj = lin("mlp.c_fc"), lin("mlp.c_proj", r)
        self.score_scale = w.score_scale
        self.scale = 1 / math.sqrt(w.D)
        if w.score_scale != 1:
            # the query rows of c_attn × 1 / (sqrt(D) × C): `scores` needs no further scaling
            q_scale = self.scale / w.score_scale
            self.qkv.weight.data[: w.E] *= q_scale
            self.qkv.bias.data[: w.E] *= q_scale
        self.H, self.D, self.E = w.H, w.D, w.E

    def scores(self, q, k):
        """Attention logits (/ C with a score scale)."""
        s = q @ k.transpose(-1, -2)
        return s if self.score_scale != 1 else s * self.scale

    def attend(self, s, v, sv=None, split=None):
        """Softmax of the logits s over the last axis, times the values v; with `sv`, the axis holds `split` prompt
        slots (values v), then the output slots (values sv)."""
        if self.score_scale != 1:
            s = (s - s.amax(dim=-1, keepdim=True)) * self.score_scale
        a = torch.softmax(s, dim=-1)
        if sv is None:
            return a @ v
        return a[..., :split] @ v + a[..., split:] @ sv

    def mlp(self, h):
        return self.mproj(F.gelu(self.fc(self.ln2(h)), approximate="tanh"))

    def split(self, a):  # (B, S, E) -> 3 x (B, H, S, D)
        q, k, v = self.qkv(a).split(self.E, dim=-1)
        f = lambda t: t.unflatten(-1, (self.H, self.D)).transpose(1, 2)
        return f(q), f(k), f(v)

    def merge(self, o):
        return self.proj(o.transpose(1, 2).flatten(2))


class Stateful(torch.nn.Module):
    """Layers lo ..< hi of the model (with the embeddings if lo == 0, the head if hi == L), with the prompt KV
    (P slots) and the rows' output KV (S * B slots) of each of these layers as buffers, which become Core ML
    states."""

    def __init__(self, w, P, S, B, lo, hi):
        super().__init__()
        r = w.residual_scale
        self.first, self.last = lo == 0, hi == w.L
        if self.first:
            # the input embeddings carry the residual scale; the head (tied to wte) uses the original ones
            self.wte_in = torch.nn.Parameter(w.sd["wte.weight"] * r)
            self.wpe = torch.nn.Parameter(w.sd["wpe.weight"] * r)
        if self.last:
            self.wte = torch.nn.Parameter(w.sd["wte.weight"])
            self.lnf = torch.nn.LayerNorm(w.E, eps=w.eps * r * r)
            self.lnf.weight.data, self.lnf.bias.data = w.sd["ln_f.weight"], w.sd["ln_f.bias"]
        self.layers = list(range(lo, hi))
        self.blocks = torch.nn.ModuleList([Block(w, i) for i in self.layers])
        self.P, self.S, self.B = P, S, B
        for i in self.layers:
            for name, n in state_slots(P, S, B):
                self.register_buffer(f"{name}{i}", torch.zeros(w.H, n, w.D, dtype=torch.float16))

    def st(self, name, i):
        return getattr(self, f"{name}{i}")

    def embed(self, ids, pos):
        return self.wte_in[ids] + self.wpe[pos]

    def touch(self, h, names):
        """h + 0 × one element of the states `names` of each layer: every function of a multifunction model must use
        all states."""
        return h + sum(self.st(name, i)[0, 0, 0] for i in self.layers for name in names).to(h.dtype) * 0

    def head(self, h):
        logits = self.lnf(h) @ self.wte.t()
        return torch.log_softmax(logits.float(), dim=-1)


def state_slots(P, S, B):
    return [("pk", P), ("pv", P), ("sk", S * B), ("sv", S * B)]


class Prefill(Stateful):
    """ids / pos (1, C) (first chunk; later chunks: the previous chunk's hidden (1, C, E)) at prompt slots
    start ..< start + C (padding after the prompt is harmless: causal, and overwritten later); mask (C, P) additive
    over the prompt slots -> logp (C, V) after each token (last chunk; others: hidden)."""

    def run(self, h, start, mask):
        h = self.touch(h, ["sk", "sv"])
        C = h.shape[1]
        for i, b in zip(self.layers, self.blocks):
            q, k, v = b.split(b.ln1(h))  # (1, H, C, D)
            self.st("pk", i)[:, start[0] : start[0] + C] = k[0].half()
            self.st("pv", i)[:, start[0] : start[0] + C] = v[0].half()
            kk, vv = self.st("pk", i).to(h.dtype), self.st("pv", i).to(h.dtype)
            s = b.scores(q, kk) + mask
            h = h + b.merge(b.attend(s, vv))
            h = h + b.mlp(h)
        return self.head(h[0]) if self.last else h


class PrefillFirst(Prefill):
    def forward(self, ids, pos, start, mask):
        return self.run(self.embed(ids[0], pos[0]).unsqueeze(0), start, mask)  # (1, C, E)


class PrefillNext(Prefill):
    def forward(self, hidden, start, mask):
        return self.run(hidden, start, mask)


class Decode(Stateful):
    """tok (B, 1) at position pos (1,) (first chunk; later chunks: the previous chunk's hidden (B, 1, E)); wsel
    (S*B, B) one-hot places row r's K / V at its slot, keep (S*B, 1) = 1 - row sums of wsel; pmask (1, P) and
    smask (B, S*B) additive (smask: the row's ancestors' slots and its own new slot) -> logp (B, V) (last chunk;
    others: hidden)."""

    def run(self, h, wsel, keep, pmask, smask):
        pm = pmask.reshape(1, 1, 1, -1)
        sm = smask.unsqueeze(1).unsqueeze(1)  # (B, 1, 1, S*B)
        for i, b in zip(self.layers, self.blocks):
            q, k, v = b.split(b.ln1(h))  # (B, H, 1, D)
            kn = (wsel @ k[:, :, 0].transpose(0, 1)).to(h.dtype)  # (H, S*B, D)
            vn = (wsel @ v[:, :, 0].transpose(0, 1)).to(h.dtype)
            sk = self.st("sk", i).to(h.dtype) * keep + kn
            sv = self.st("sv", i).to(h.dtype) * keep + vn
            self.st("sk", i)[:] = sk.half()
            self.st("sv", i)[:] = sv.half()
            pk, pv = self.st("pk", i).to(h.dtype), self.st("pv", i).to(h.dtype)
            sp = b.scores(q, pk) + pm  # (B, H, 1, P)
            ss = b.scores(q, sk) + sm  # (B, H, 1, S*B)
            h = h + b.merge(b.attend(torch.cat([sp, ss], dim=-1), pv, sv, self.P))
            h = h + b.mlp(h)
        return self.head(h[:, 0]) if self.last else h


class DecodeFirst(Decode):
    def forward(self, tok, pos, wsel, keep, pmask, smask):
        return self.run(self.embed(tok[:, 0], pos).unsqueeze(1), wsel, keep, pmask, smask)  # (B, 1, E)


class DecodeNext(Decode):
    def forward(self, hidden, wsel, keep, pmask, smask):
        return self.run(hidden, wsel, keep, pmask, smask)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("hf_dir")
    ap.add_argument("out_dir")
    ap.add_argument("--P", type=int, default=256, help="prompt slots")
    ap.add_argument("--S", type=int, default=64, help="output steps")
    ap.add_argument("--B", type=int, default=5, help="rows (beams)")
    ap.add_argument("--C", type=int, default=32, help="prefill chunk")
    ap.add_argument("--chunks", type=int, default=1, help="functions the layers are split into")
    ap.add_argument("--residual-scale", type=float, default=1.0, help="residual stream scale (fp16 range)")
    ap.add_argument("--score-scale", type=float, default=1.0, help="attention logit divisor (fp16 range)")
    a = ap.parse_args()
    P, S, B, C, N = a.P, a.S, a.B, a.C, a.chunks
    out = a.out_dir
    os.makedirs(out, exist_ok=True)
    w = Weights(a.hf_dir, a.residual_scale, a.score_scale)
    f16, i32 = np.float16, torch.int32
    def states(lo, hi):
        return [
            ct.StateType(wrapped_type=ct.TensorType(shape=(w.H, n, w.D), dtype=f16), name=f"{name}{i}")
            for i in range(lo, hi)
            for name, n in state_slots(P, S, B)
        ]

    quantize = OptimizationConfig(
        global_config=OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8", granularity="per_channel"))

    def convert(module, example, inputs, output, name):
        traced = torch.jit.trace(module.eval(), example)
        dtype = np.float32 if output == "logp" else f16
        m = ct.convert(
            traced, inputs=inputs, outputs=[ct.TensorType(output, dtype=dtype)], states=states(*module_range(module)),
            minimum_deployment_target=ct.target.iOS18, compute_precision=ct.precision.FLOAT16)
        path = f"{out}/{name}.mlpackage"
        shutil.rmtree(path, ignore_errors=True)
        linear_quantize_weights(m, quantize).save(path)
        return path

    def module_range(module):
        return module.layers[0], module.layers[-1] + 1

    bounds = [w.L * k // N for k in range(N + 1)]
    packages = []
    with torch.no_grad():
        for k in range(N):
            lo, hi = bounds[k], bounds[k + 1]
            output = "logp" if hi == w.L else "hidden"
            suffix = "" if N == 1 else f"_{k}"
            masks = [ct.TensorType("start", shape=(1,), dtype=np.int32), ct.TensorType("mask", shape=(C, P), dtype=f16)]
            example = (torch.zeros(1, dtype=i32), torch.zeros(C, P))
            if lo == 0:
                p = convert(PrefillFirst(w, P, S, B, lo, hi), (torch.zeros(1, C, dtype=i32), torch.zeros(1, C, dtype=i32)) + example, [
                    ct.TensorType("ids", shape=(1, C), dtype=np.int32), ct.TensorType("pos", shape=(1, C), dtype=np.int32)] + masks,
                    output, "prefill_part")
            else:
                p = convert(PrefillNext(w, P, S, B, lo, hi), (torch.zeros(1, C, w.E),) + example,
                            [ct.TensorType("hidden", shape=(1, C, w.E), dtype=f16)] + masks, output, "prefill_part")
            sel = [ct.TensorType("wsel", shape=(S * B, B), dtype=f16), ct.TensorType("keep", shape=(S * B, 1), dtype=f16),
                   ct.TensorType("pmask", shape=(1, P), dtype=f16), ct.TensorType("smask", shape=(B, S * B), dtype=f16)]
            example = (torch.zeros(S * B, B), torch.zeros(S * B, 1), torch.zeros(1, P), torch.zeros(B, S * B))
            if lo == 0:
                d = convert(DecodeFirst(w, P, S, B, lo, hi), (torch.zeros(B, 1, dtype=i32), torch.zeros(1, dtype=i32)) + example, [
                    ct.TensorType("tok", shape=(B, 1), dtype=np.int32), ct.TensorType("pos", shape=(1,), dtype=np.int32)] + sel,
                    output, "decode_part")
            else:
                d = convert(DecodeNext(w, P, S, B, lo, hi), (torch.zeros(B, 1, w.E),) + example,
                            [ct.TensorType("hidden", shape=(B, 1, w.E), dtype=f16)] + sel, output, "decode_part")
            # one multifunction package per chunk, with its own states (a package with the weights of more than
            # ~12 layers of genmai-310M does not load on the Neural Engine)
            desc = ct.utils.MultiFunctionDescriptor()
            desc.add_function(p, src_function_name="main", target_function_name="prefill")
            desc.add_function(d, src_function_name="main", target_function_name="decode")
            desc.default_function_name = "decode"
            package = f"{out}/genmai{suffix}.mlpackage"
            shutil.rmtree(package, ignore_errors=True)
            ct.utils.save_multifunction(desc, package)
            shutil.rmtree(p)
            shutil.rmtree(d)
            packages.append(package)
    meta = {"format": FORMAT, "prompt_slots": P, "output_steps": S, "rows": B, "prefill_chunk": C}
    if N > 1:
        meta["chunks"] = N
    if a.residual_scale != 1 or a.score_scale != 1:
        meta |= {"residual_scale": a.residual_scale, "score_scale": a.score_scale}
    with open(f"{out}/genmai_coreml.json", "w") as f:
        json.dump(meta, f, indent=2)
        f.write("\n")
    for name in ("config.json", "tokenizer.json"):
        shutil.copy(f"{a.hf_dir}/{name}", f"{out}/{name}")
    with zipfile.ZipFile(f"{out}/{ARCHIVE}", "w", zipfile.ZIP_DEFLATED) as z:
        z.write(f"{out}/genmai_coreml.json", "genmai_coreml.json")
        for package in packages:
            base = os.path.dirname(package)
            for root, _, files in sorted(os.walk(package)):
                for name in sorted(files):
                    path = os.path.join(root, name)
                    z.write(path, os.path.relpath(path, base))


if __name__ == "__main__":
    main()
