// genmai model: beam-search kana-kanji conversion with a GPT-2 (zenz-style, char-level) model on MLX.
//
// Port of the Python MLX reference decoder (`MLXConverter`): GPT-2 with a static KV cache; one decode step (beam
// reorder + 24 layers + log-softmax) is a compiled function per (rows, cache bucket). Decoding matches
// fast_graph / gen_eval: sum of log-probs (length_penalty 0), stop once `beams` hypotheses ended,
// max_new = 1.3 * reading + 8, optional min-ratio EOS ban, text cut at the first newline. `convert` splits long
// readings at punctuation (chunk 40) and beams across chunks; `genBatch` decodes the hypotheses of a chunk
// (several left contexts) as one batch with left-padded prompts and per-row position ids / masks.
//
// Speed notes (M4 Pro, from the Python port): weights are stored (out, in) and used as `x @ W.T`, which hits
// MLX's fast matrix-vector kernel at small batch (3x faster at batch 5); bf16 is the right dtype (fp32 is ~2.5x
// slower, fp16 overflows to NaN).

import Foundation
import MLX
import MLXNN
import Cmlx

/// One conversion result: the converted text and its total log-probability.
public struct GenmaiCandidate: Sendable, Hashable {
    public var text: String
    public var score: Double

    public init(text: String, score: Double) {
        self.text = text
        self.score = score
    }
}

public struct GenmaiOptions: Sendable, Hashable {
    /// Beam width (and number of returned candidates).
    public var beams: Int = 5
    /// Readings longer than this are split at punctuation into chunks of at most this many characters.
    public var chunk: Int = 40
    /// Beam width per hypothesis when continuing a chunked conversion.
    public var chunkBeams: Int = 4
    /// Forbid EOS until the output has at least `minRatio * reading length` tokens (0 = off).
    public var minRatio: Double = 0
    /// Reuse the KV cache of earlier prompts that share a token prefix with this one (the left context and the
    /// reading typed so far); only the new prompt tail is prefilled.
    public var reusePromptKV: Bool = true
    /// Draft-and-verify: the previous top-1 output under the same left context is appended to the prompt and
    /// verified in the prefill; its longest prefix whose every token is the argmax by at least `draftMargin`
    /// (log-prob) is accepted and the beam search starts after it. Fewer decode steps; the n-best alternatives
    /// then share that prefix (not an exact beam search, see CLAUDE.md for the accuracy impact).
    public var draft: Bool = false
    public var draftMargin: Float = 2

    public init(beams: Int = 5, chunk: Int = 40, chunkBeams: Int = 4, minRatio: Double = 0, reusePromptKV: Bool = true,
                draft: Bool = false, draftMargin: Float = 2) {
        self.beams = beams
        self.chunk = chunk
        self.chunkBeams = chunkBeams
        self.minRatio = minRatio
        self.reusePromptKV = reusePromptKV
        self.draft = draft
        self.draftMargin = draftMargin
    }
}

public enum GenmaiError: Error, CustomStringConvertible {
    case missingFile(URL)
    case badModel(String)

    public var description: String {
        switch self {
        case .missingFile(let u): "missing model file: \(u.path)"
        case .badModel(let s): "bad genmai model: \(s)"
        }
    }
}

/// Model configuration (subset of the HF GPT-2 config.json).
public struct GenmaiConfig: Sendable, Codable {
    public var nLayer: Int
    public var nEmbd: Int
    public var nHead: Int
    public var layerNormEpsilon: Float
    public var vocabSize: Int
    public var nPositions: Int
    /// The prompt format the model was trained with (`genmai_prompt_format`; only "zenzlc" is supported).
    public var promptFormat: String?

    enum CodingKeys: String, CodingKey {
        case nLayer = "n_layer", nEmbd = "n_embd", nHead = "n_head", layerNormEpsilon = "layer_norm_epsilon"
        case vocabSize = "vocab_size", nPositions = "n_positions", promptFormat = "genmai_prompt_format"
    }
}

/// The genmai model and its synchronous decoder. Not Sendable (MLX arrays are not): use it through the
/// `GenmaiConverter` actor, which owns one instance.
public final class GenmaiModel {
    /// KV cache sizes; a decode step is compiled per (rows, bucket).
    public static let buckets = [128, 256, 512, 1024]
    /// Metadata value of `format` in a safetensors file written by GenmaiClient's `GenmaiSafetensors.prepare` (the
    /// model installer, `genmai-cli prepare`): bf16 weights with the Conv1D matrices already transposed to (out, in).
    public static let preparedFormat = "genmai-bf16-out-in"

    public let config: GenmaiConfig
    public let tokenizer: GenmaiTokenizer
    /// Seconds spent in `init` (reading + converting the weights, tokenizer).
    public let loadSeconds: Double

    private struct Layer {
        let ln1w, ln1b, attnW, attnB, projW, projB, ln2w, ln2b, fcW, fcB, mlpProjW, mlpProjB: MLXArray
    }

    private let layers: [Layer]
    private let wte: MLXArray
    private let wpe: MLXArray
    private let lnfW: MLXArray
    private let lnfB: MLXArray
    private let dtype: DType = .bfloat16
    private let L: Int
    private let D: Int
    private let H: Int
    private let hd: Int
    private let eps: Float
    private let eos: Int32
    private var steps: [StepKey: @Sendable ([MLXArray]) -> [MLXArray]] = [:]

    /// KV of recent prompts (one row each, (1, H, n, hd) per layer), most recently used last. A new prompt reuses
    /// the entry with the longest common token prefix: while typing, the next prompt shares everything up to the
    /// end of the reading (context first, then the reading; only the new kana and the output marker differ).
    private struct PromptKV {
        let ids: [Int32]
        let K: [MLXArray]
        let V: [MLXArray]
    }

    private var promptCache: [PromptKV] = []
    /// Budget of the prompt KV cache in tokens (~98 KB per token: 24 layers x K/V x 1024 x bf16).
    static let promptCacheTokens = 4096
    /// The best output of recent searches, keyed by their left context (most recent last): the drafts of
    /// draft-and-verify decoding.
    private var drafts: [(context: String, tokens: [Int32])] = []
    static let maxDrafts = 16
    /// Draft tokens verified per row at most.
    static let maxDraftTokens = 128
    /// Statistics of draft-and-verify (diagnostics): output tokens accepted from drafts / decode steps run.
    public private(set) var draftTokensAccepted = 0
    public private(set) var decodeSteps = 0

    /// Statistics of the prompt KV reuse (diagnostics): prompt tokens prefilled / reused.
    public private(set) var promptTokensPrefilled = 0
    public private(set) var promptTokensReused = 0

    private struct StepKey: Hashable {
        let rows: Int
        let bucket: Int
    }

    /// Loads `config.json`, `tokenizer.json` and `model.safetensors` from `directory`. The weights may be the
    /// original HF fp32 file (converted to bf16 / (out, in) here) or a file written by the model installer.
    public init(directory: URL) throws {
        let t0 = Date()
        Self.configureMetallib()
        let cfgURL = directory.appending(path: "config.json")
        let tokURL = directory.appending(path: "tokenizer.json")
        let wURL = directory.appending(path: "model.safetensors")
        for u in [cfgURL, tokURL, wURL] where !FileManager.default.fileExists(atPath: u.path) {
            throw GenmaiError.missingFile(u)
        }
        let cfg = try JSONDecoder().decode(GenmaiConfig.self, from: Data(contentsOf: cfgURL))
        if let fmt = cfg.promptFormat, fmt != "zenzlc" {
            throw GenmaiError.badModel("prompt format \(fmt) (only zenzlc is supported)")
        }
        let w = try Self.loadWeights(wURL, dtype: .bfloat16)
        func get(_ k: String) throws -> MLXArray {
            guard let a = w[k] else { throw GenmaiError.badModel("missing tensor \(k)") }
            return a
        }
        var layers: [Layer] = []
        for i in 0..<cfg.nLayer {
            let p = "h.\(i)."
            layers.append(
                Layer(
                    ln1w: try get(p + "ln_1.weight"), ln1b: try get(p + "ln_1.bias"),
                    attnW: try get(p + "attn.c_attn.weight"), attnB: try get(p + "attn.c_attn.bias"),
                    projW: try get(p + "attn.c_proj.weight"), projB: try get(p + "attn.c_proj.bias"),
                    ln2w: try get(p + "ln_2.weight"), ln2b: try get(p + "ln_2.bias"),
                    fcW: try get(p + "mlp.c_fc.weight"), fcB: try get(p + "mlp.c_fc.bias"),
                    mlpProjW: try get(p + "mlp.c_proj.weight"), mlpProjB: try get(p + "mlp.c_proj.bias")))
        }
        self.layers = layers
        self.wte = try get("wte.weight")
        self.wpe = try get("wpe.weight")
        self.lnfW = try get("ln_f.weight")
        self.lnfB = try get("ln_f.bias")
        eval(Array(w.values))
        self.config = cfg
        self.L = cfg.nLayer
        self.D = cfg.nEmbd
        self.H = cfg.nHead
        self.hd = cfg.nEmbd / cfg.nHead
        self.eps = cfg.layerNormEpsilon
        let tok = try GenmaiTokenizer(url: tokURL)
        self.tokenizer = tok
        self.eos = tok.eosTokenID
        self.loadSeconds = Date().timeIntervalSince(t0)
    }

    /// Points MLX at a Metal library when its own lookup (a colocated `mlx.metallib`, then
    /// `mlx-swift_Cmlx.bundle` in the main bundle) would fail or pick the fast-math build, e.g. under `swift test`,
    /// whose main bundle is the test runner. Order: $GENMAI_MLX_METALLIB, then `mlx.metallib` and
    /// `mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib` next to the binary or bundle containing GenmaiAI
    /// (Tools/build_mlx_metallib.sh writes the safe-math `mlx.metallib` there). Does nothing if MLX's override path
    /// is already set or nothing is found.
    static func configureMetallib() {
        guard GPU.metallib == nil else { return }
        let fm = FileManager.default
        if let e = ProcessInfo.processInfo.environment["GENMAI_MLX_METALLIB"], fm.fileExists(atPath: e) {
            GPU.metallib = URL(filePath: e)
            return
        }
        let bundle = Bundle(for: GenmaiModel.self)
        var dirs: [URL] = []
        if let exe = bundle.executableURL { dirs.append(exe.deletingLastPathComponent()) }
        if bundle.bundleURL.pathExtension.isEmpty {
            dirs.append(bundle.bundleURL)
        } else {
            dirs.append(bundle.bundleURL.deletingLastPathComponent())  // e.g. .build/debug for the .xctest bundle
        }
        if let r = bundle.resourceURL { dirs.append(r) }
        for name in ["mlx.metallib", "mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"] {
            for d in dirs {
                let u = d.appending(path: name)
                if fm.fileExists(atPath: u.path) {
                    // a colocated mlx.metallib / the main bundle's resource bundle are found by MLX itself
                    if d == dirs.first && name == "mlx.metallib" { return }
                    GPU.metallib = u
                    return
                }
            }
        }
    }

    /// Reads a safetensors file and returns the weights keyed without the `transformer.` prefix, in `dtype`, with
    /// the Conv1D matrices as (out, in) contiguous arrays.
    static func loadWeights(_ url: URL, dtype: DType) throws -> [String: MLXArray] {
        let (arrays, meta) = try loadArraysAndMetadata(url: url)
        let prepared = meta["format"] == preparedFormat
        var w: [String: MLXArray] = [:]
        for (k0, v) in arrays {
            let k = k0.hasPrefix("transformer.") ? String(k0.dropFirst("transformer.".count)) : k0
            if k == "lm_head.weight" { continue }  // tied to wte
            var a = v.dtype == dtype ? v : v.asType(dtype)
            if !prepared && (k.hasSuffix("c_attn.weight") || k.hasSuffix("c_proj.weight") || k.hasSuffix("c_fc.weight")) {
                // HF Conv1D weights are (in, out)
                a = contiguous(a.T)
            }
            w[k] = a
        }
        return w
    }

    // MARK: - Model

    /// `mx.slice_update(src, update, start, axes)` with a dynamic (array) start, which the Swift API does not wrap.
    private static func sliceUpdate(_ src: MLXArray, _ update: MLXArray, start: MLXArray, axes: [Int32]) -> MLXArray {
        var res = mlx_array_new()
        axes.withUnsafeBufferPointer { ax in
            _ = mlx_slice_update_dynamic(&res, src.ctx, update.ctx, start.ctx, ax.baseAddress, ax.count, StreamOrDevice.default.ctx)
        }
        return MLXArray(res)
    }

    /// ids (B,S); posIDs (B,S); start: int32 scalar, cache slot of ids[:, 0] (shared by all rows); K/V: (B,H,T,hd);
    /// mask additive (B|1,1,S,T). Returns last-position log-probs (B, vocab) float32 and the updated caches.
    /// With `outputFrom`, returns the log-probs of positions outputFrom..<S as (B, S - outputFrom, vocab).
    private func forward(_ ids: MLXArray, _ posIDs: MLXArray, _ start: MLXArray, _ K: [MLXArray], _ V: [MLXArray],
                         _ mask: MLXArray, outputFrom: Int? = nil) -> (MLXArray, [MLXArray], [MLXArray])
    {
        let B = ids.dim(0)
        let S = ids.dim(1)
        var h = wte.take(ids, axis: 0) + wpe.take(posIDs, axis: 0)
        let start1 = start.reshaped([1])
        var K2: [MLXArray] = []
        var V2: [MLXArray] = []
        K2.reserveCapacity(L)
        V2.reserveCapacity(L)
        let scale = 1 / Float(hd).squareRoot()
        for (i, p) in layers.enumerated() {
            var a = MLXFast.layerNorm(h, weight: p.ln1w, bias: p.ln1b, eps: eps)
            let qkv = matmul(a, p.attnW.T) + p.attnB
            let parts = qkv.split(parts: 3, axis: -1).map { $0.reshaped([B, S, H, hd]).transposed(0, 2, 1, 3) }
            let kc = Self.sliceUpdate(K[i], parts[1], start: start1, axes: [2])
            let vc = Self.sliceUpdate(V[i], parts[2], start: start1, axes: [2])
            K2.append(kc)
            V2.append(vc)
            let o = MLXFast.scaledDotProductAttention(queries: parts[0], keys: kc, values: vc, scale: scale, mask: mask)
            h = h + matmul(o.transposed(0, 2, 1, 3).reshaped([B, S, D]), p.projW.T) + p.projB
            a = MLXFast.layerNorm(h, weight: p.ln2w, bias: p.ln2b, eps: eps)
            h = h + matmul(geluApproximate(matmul(a, p.fcW.T) + p.fcB), p.mlpProjW.T) + p.mlpProjB
        }
        let last = MLXFast.layerNorm(outputFrom.map { h[0..., $0...] } ?? h[0..., -1], weight: lnfW, bias: lnfB, eps: eps)
        let logits = matmul(last, wte.T).asType(.float32)
        return (logits - logits.logSumExp(axis: -1, keepDims: true), K2, V2)
    }

    private func getStep(rows B: Int, bucket T: Int) -> @Sendable ([MLXArray]) -> [MLXArray] {
        let key = StepKey(rows: B, bucket: T)
        if let s = steps[key] { return s }
        let ar = MLXArray(Int32(0)..<Int32(T))
        let L = self.L
        let dt = dtype
        // inputs: tok (B), src (B), pos (scalar), pad (B), K[0..L), V[0..L); outputs: logp, K, V
        let f: ([MLXArray]) -> [MLXArray] = { [self] args in
            let tok = args[0], src = args[1], pos = args[2], pad = args[3]
            let K = args[4..<(4 + L)].map { $0.take(src, axis: 0) }
            let V = args[(4 + L)..<(4 + 2 * L)].map { $0.take(src, axis: 0) }
            let ok = (ar.expandedDimensions(axis: 0) .<= pos) .&& (ar.expandedDimensions(axis: 0) .>= pad.expandedDimensions(axis: 1))
            let mask = MLX.where(ok, MLXArray(Float(0)), MLXArray(-Float.infinity)).asType(dt).reshaped([B, 1, 1, T])
            let (lp, K2, V2) = self.forward(tok.reshaped([B, 1]), (pos - pad).reshaped([B, 1]), pos, K, V, mask)
            return [lp] + K2 + V2
        }
        let s = compile(f)
        steps[key] = s
        return s
    }

    /// Compiles the decode steps that typical conversions use (rows 4/5/8/12/16/20, all buckets: the IME's left
    /// context of up to 500 characters needs 1024), then runs
    /// one short conversion so that the Metal kernels of the prefill are JIT-compiled too (the first conversion
    /// otherwise takes ~2 s).
    public func warmup(rows: [Int] = [4, 5, 8, 12, 16, 20]) {
        defer { _ = try? convert("きょうはいいてんきですね", context: "あ") }
        for B in rows {
            for T in Self.buckets {
                let z = (0..<L).map { _ in MLXArray.zeros([B, H, T, hd], dtype: dtype) }
                let out = getStep(rows: B, bucket: T)(
                    [MLXArray.zeros([B], dtype: .int32), MLXArray(Int32(0)..<Int32(B)), MLXArray(Int32(0)),
                     MLXArray.zeros([B], dtype: .int32)] + z + z)
                eval(out)
            }
        }
    }

    /// Diagnostics (parity checks against the Python port): log-probs of the next token after the prompt, for the
    /// given token ids appended to the prompt one by one through the compiled decode step (1 row).
    public func debugLogProbs(_ reading: String, context: String = "", continuation: [Int32] = []) -> [[Float]] {
        let prompt = GenmaiPrompt.ids(tokenizer, reading: reading, context: context)
        let P = prompt.count
        let T = Self.buckets.first { $0 >= P + continuation.count + 1 }!
        let q = MLXArray(Int32(0)..<Int32(P)).reshaped([1, P, 1])
        let kk = MLXArray(Int32(0)..<Int32(T)).reshaped([1, 1, T])
        let mask = MLX.where(kk .<= q, MLXArray(Float(0)), MLXArray(-Float.infinity)).asType(dtype).reshaped([1, 1, P, T])
        let z = (0..<L).map { _ in MLXArray.zeros([1, H, T, hd], dtype: dtype) }
        var (lp, K, V) = forward(MLXArray(prompt, [1, P]), MLXArray(Int32(0)..<Int32(P)).reshaped([1, P]), MLXArray(Int32(0)), z, z, mask)
        var res = [lp.asArray(Float.self)]
        let step = getStep(rows: 1, bucket: T)
        for (i, t) in continuation.enumerated() {
            let out = step([MLXArray([t]), MLXArray([Int32(0)]), MLXArray(Int32(P + i)), MLXArray([Int32(0)])] + K + V)
            lp = out[0]
            K = Array(out[1...L])
            V = Array(out[(L + 1)...(2 * L)])
            res.append(lp.asArray(Float.self))
        }
        return res
    }

    // MARK: - Beam search

    public func gen(_ reading: String, context: String = "", beams: Int = 5, minRatio: Double = 0) throws -> [GenmaiCandidate] {
        try genBatch(reading, contexts: [context], beams: beams, minRatio: minRatio)[0]
    }

    /// Independent beam searches for one reading under several left contexts, decoded as one batch
    /// (G groups x `beams` rows). Returns, per context, the candidates (text, sum log-prob) best first.
    /// Throws `CancellationError` (checked between decode steps) when the task is cancelled.
    public func genBatch(_ reading: String, contexts: [String], beams b: Int = 5, minRatio: Double = 0,
                         reusePromptKV: Bool = true, draft: Bool = false, draftMargin: Float = 2) throws
        -> [[GenmaiCandidate]]
    {
        try Task.checkCancellation()  // a stale job queued behind the MLX lock skips the prefill too
        let G = contexts.count
        let readingLength = reading.unicodeScalars.count
        let maxNew = Int(Double(readingLength) * 1.3) + 8
        let maxT = Self.buckets.last!
        var prompts: [[Int32]] = []
        for ctx in contexts {
            var ids = GenmaiPrompt.ids(tokenizer, reading: reading, context: ctx)
            if ids.count + maxNew > maxT {  // keep BOS + prompt tail
                ids = [ids[0]] + ids.suffix(maxT - maxNew - 1)
            }
            prompts.append(ids)
        }
        let P = prompts.map(\.count).max()!
        guard let T = Self.buckets.first(where: { $0 >= P + maxNew }) else {
            throw GenmaiError.badModel("prompt too long")
        }
        let pads = prompts.map { Int32(P - $0.count) }
        // Prompt KV reuse: row g takes the first reuse[g] tokens' KV from the cache; the forward pass computes the
        // last S slots [q0, P) of every row (at least the last prompt token, whose log-probs start the search).
        // Rows that reuse less recompute some cached slots, which only overwrites them with the same values.
        var reuse = [Int](repeating: 0, count: G)
        var entries: [PromptKV?] = Array(repeating: nil, count: G)
        if reusePromptKV {
            for g in 0..<G {
                if let (e, n) = lookupPrompt(prompts[g]) {
                    entries[g] = e
                    reuse[g] = min(n, prompts[g].count - 1)
                }
            }
        }
        let S = (0..<G).map { prompts[$0].count - reuse[$0] }.max()!
        let q0 = P - S
        let used = (0..<G).map { max(0, q0 - Int(pads[$0])) }  // cached tokens placed at [pad, q0)
        promptTokensPrefilled += (0..<G).map { prompts[$0].count - used[$0] }.reduce(0, +)
        promptTokensReused += used.reduce(0, +)
        // Drafts: the previous best output under each context, appended to the prompt (slots [P, P + D)); the
        // causal mask covers them like prompt tokens (shorter drafts are padded at the end, never attended).
        let draftTokens: [[Int32]] = draft
            ? contexts.map { c in Array((drafts.last { $0.context == c }?.tokens ?? []).prefix(min(Self.maxDraftTokens, maxNew - 2))) }
            : Array(repeating: [], count: G)
        let D = draftTokens.map(\.count).max() ?? 0
        let Q = S + D
        // prefill (G rows, left-padded); pad query rows attend to themselves only to avoid all -inf rows
        let ar = MLXArray(Int32(q0)..<Int32(P + D))
        let padv = MLXArray(pads)
        let q = ar.reshaped([1, Q, 1])
        let kk = MLXArray(Int32(0)..<Int32(T)).reshaped([1, 1, T])
        let padv3 = padv.reshaped([G, 1, 1])
        let ok = ((kk .<= q) .&& (kk .>= padv3)) .|| (kk .== q)
        let mask = MLX.where(ok, MLXArray(Float(0)), MLXArray(-Float.infinity)).asType(dtype).reshaped([G, 1, Q, T])
        var flat: [Int32] = []
        flat.reserveCapacity(G * Q)
        for (g, (p, x)) in zip(pads, prompts).enumerated() {
            for slot in q0..<P {
                flat.append(slot >= Int(p) ? x[slot - Int(p)] : 0)
            }
            for k in 0..<D {
                flat.append(k < draftTokens[g].count ? draftTokens[g][k] : 0)
            }
        }
        let ids = MLXArray(flat, [G, Q])
        let posIDs = maximum(ar.expandedDimensions(axis: 0) - padv.expandedDimensions(axis: 1), MLXArray(Int32(0)))
        let (K0, V0) = initialCache(rows: G, bucket: T, pads: pads.map(Int.init), used: used, entries: entries)
        var (lp, K, V) = forward(ids, posIDs, MLXArray(Int32(q0)), K0, V0, mask, outputFrom: D > 0 ? S - 1 : nil)
        if reusePromptKV {
            storePrompts(prompts, pads: pads.map(Int.init), P: P, K: K, V: V)
        }
        K = K.map { repeated($0, count: b, axis: 0) }
        V = V.map { repeated($0, count: b, axis: 0) }
        // Accept the longest common draft prefix (over all rows) whose tokens are the argmax by `draftMargin`.
        var start = 0
        var prefixScores = [Float](repeating: 0, count: G)
        if D > 0 {
            let all = lp  // (G, 1 + D, vocab): after the prompt, after each draft token
            let top2 = argPartition(-all, kth: 1, axis: -1)[0..., 0..., ..<2]
            let t2 = top2.asArray(Int32.self)
            let v2 = takeAlong(all, top2, axis: -1).asArray(Float.self)
            var accepted = Int.max
            var sums: [[Float]] = []
            for g in 0..<G {
                var a = 0
                var sum: [Float] = [0]
                while a < draftTokens[g].count {
                    let i = (g * (1 + D) + a) * 2
                    let first = v2[i] >= v2[i + 1] ? 0 : 1
                    guard t2[i + first] == draftTokens[g][a], v2[i + first] - v2[i + 1 - first] >= draftMargin else { break }
                    sum.append(sum[a] + v2[i + first])
                    a += 1
                }
                sums.append(sum)
                accepted = min(accepted, a)
            }
            start = accepted
            for g in 0..<G { prefixScores[g] = sums[g][start] }
            lp = all[0..., start]
            draftTokensAccepted += start * G
        }
        let Vn = lp.dim(1)
        let eosCol = MLXArray(Int32(0)..<Int32(Vn)) .== MLXArray(eos)
        let minLen = Int(Double(readingLength) * minRatio)
        let negInf = MLXArray(-Float.infinity)
        if minLen > 0 && start + 1 < minLen {
            lp = MLX.where(eosCol.expandedDimensions(axis: 0), negInf, lp)
        }
        var toks = argSort(-lp, axis: -1)[0..., ..<b]  // (G, b)
        var scores = takeAlong(lp, toks, axis: -1)
        if start > 0 {
            scores = scores + MLXArray(prefixScores).reshaped([G, 1])
        }
        var tokL = toks.asArray(Int32.self)
        var scL = scores.asArray(Float.self)
        var seqs: [[[Int32]]] = (0..<G).map { g in (0..<b).map { Array(draftTokens[g].prefix(start)) + [tokL[g * b + $0]] } }
        var done: [[(seq: [Int32], score: Float)]] = (0..<G).map { g in
            (0..<b).compactMap { i in seqs[g][i].last == eos ? (seqs[g][i], scL[g * b + i]) : nil }
        }
        var dead = toks .== MLXArray(eos)
        let R = G * b
        var src = MLXArray(Int32(0)..<Int32(R))
        let base = (MLXArray(Int32(0)..<Int32(G)) * Int32(b)).expandedDimensions(axis: 1)
        let padRows = repeated(padv, count: b, axis: 0)
        let step = getStep(rows: R, bucket: T)
        defer {
            // the next search's draft: this search's best sequence (also when cancelled)
            do {
                for g in 0..<G {
                    let best = Self.stableSorted(done[g]) { $0.score > $1.score }.first?.seq ?? seqs[g][0]
                    storeDraft(contexts[g], best.filter { $0 != eos })
                }
            }
        }
        for i in start..<max(start, maxNew - 1) {
            let fin = done.map { $0.count >= b }
            if fin.allSatisfy({ $0 }) { break }
            try Task.checkCancellation()
            let out = step([toks.reshaped([-1]), src, MLXArray(Int32(P + i)), padRows] + K + V)
            decodeSteps += 1
            K = Array(out[1...L])
            V = Array(out[(L + 1)...(2 * L)])
            var cand = out[0].reshaped([G, b, Vn]) + scores.expandedDimensions(axis: 2)
            if i + 2 < minLen {
                cand = MLX.where(eosCol.reshaped([1, 1, Vn]), negInf, cand)
            }
            let finA = MLXArray(fin).reshaped([G, 1, 1])
            cand = MLX.where(dead.expandedDimensions(axis: 2) .|| finA, negInf, cand).reshaped([G, b * Vn])
            var ix = argPartition(-cand, kth: b - 1, axis: -1)[0..., ..<b]
            var v = takeAlong(cand, ix, axis: -1)
            let order = argSort(-v, axis: -1)
            ix = takeAlong(ix, order, axis: -1)
            v = takeAlong(v, order, axis: -1)
            let srcG = ix.floorDivide(Vn)
            toks = ix % Vn
            scores = v
            src = (srcG + base).reshaped([-1])
            let srcL = srcG.asArray(Int32.self)
            tokL = toks.asArray(Int32.self)
            scL = v.asArray(Float.self)
            dead = toks .== MLXArray(eos)
            for g in 0..<G where !fin[g] {
                let old = seqs[g]
                seqs[g] = (0..<b).map { j in old[Int(srcL[g * b + j])] + [tokL[g * b + j]] }
                for j in 0..<b where tokL[g * b + j] == eos && scL[g * b + j].isFinite {
                    done[g].append((seqs[g][j], scL[g * b + j]))
                }
            }
        }
        var resAll: [[GenmaiCandidate]] = []
        for g in 0..<G {
            var dg = done[g]
            if dg.count < b {
                for j in 0..<b where seqs[g][j].last != eos && scL[g * b + j].isFinite {
                    dg.append((seqs[g][j], scL[g * b + j]))
                }
            }
            let sorted = Self.stableSorted(dg) { $0.score > $1.score }
            var res: [GenmaiCandidate] = []
            var seen = Set<String>()
            for (sq, sc) in sorted.prefix(b) {
                var t = tokenizer.decode(sq.filter { $0 != eos })
                if let nl = t.firstIndex(of: "\n") { t = String(t[..<nl]) }
                if seen.insert(t).inserted {
                    res.append(GenmaiCandidate(text: t, score: Double(sc)))
                }
            }
            resAll.append(res)
        }
        return resAll
    }

    // MARK: - Prompt KV cache

    /// The cached prompt with the longest common token prefix with `ids` (at least 2 tokens), moved to the end.
    private func lookupPrompt(_ ids: [Int32]) -> (PromptKV, Int)? {
        var best = 1
        var index: Int?
        for (i, e) in promptCache.enumerated() {
            let n = zip(e.ids, ids).prefix { $0 == $1 }.count
            if n > best {
                best = n
                index = i
            }
        }
        guard let index else { return nil }
        let e = promptCache.remove(at: index)
        promptCache.append(e)
        return (e, best)
    }

    /// The prefill's KV cache: zeros, with row g's slots [pads[g], pads[g] + used[g]) taken from `entries[g]`.
    private func initialCache(rows G: Int, bucket T: Int, pads: [Int], used: [Int], entries: [PromptKV?])
        -> ([MLXArray], [MLXArray])
    {
        guard used.contains(where: { $0 > 0 }) else {
            let z = (0..<L).map { _ in MLXArray.zeros([G, H, T, hd], dtype: dtype) }
            return (z, z)
        }
        func build(_ cached: (PromptKV) -> [MLXArray]) -> [MLXArray] {
            (0..<L).map { l in
                let rows = (0..<G).map { g -> MLXArray in
                    guard used[g] > 0, let e = entries[g] else { return MLXArray.zeros([1, H, T, hd], dtype: dtype) }
                    var parts: [MLXArray] = []
                    if pads[g] > 0 { parts.append(MLXArray.zeros([1, H, pads[g], hd], dtype: dtype)) }
                    parts.append(cached(e)[l][0..., 0..., ..<used[g]])
                    let rest = T - pads[g] - used[g]
                    if rest > 0 { parts.append(MLXArray.zeros([1, H, rest, hd], dtype: dtype)) }
                    return concatenated(parts, axis: 2)
                }
                return G == 1 ? rows[0] : concatenated(rows, axis: 0)
            }
        }
        return (build(\.K), build(\.V))
    }

    /// Remembers the KV of each prompt (row g: slots [pads[g], P)), within the token budget.
    private func storePrompts(_ prompts: [[Int32]], pads: [Int], P: Int, K: [MLXArray], V: [MLXArray]) {
        var added: [PromptKV] = []
        for (g, ids) in prompts.enumerated() {
            if added.contains(where: { $0.ids == ids }) { continue }
            let k = K.map { contiguous($0[g..<(g + 1), 0..., pads[g]..<P]) }
            let v = V.map { contiguous($0[g..<(g + 1), 0..., pads[g]..<P]) }
            added.append(PromptKV(ids: ids, K: k, V: v))
        }
        eval(added.flatMap { $0.K + $0.V })
        promptCache.removeAll { e in added.contains { $0.ids == e.ids } }
        promptCache += added
        var total = promptCache.map(\.ids.count).reduce(0, +)
        while total > Self.promptCacheTokens, promptCache.count > 1 {
            total -= promptCache.removeFirst().ids.count
        }
    }

    /// Drops the prompt KV cache and the drafts (tests, memory pressure).
    public func clearPromptCache() {
        promptCache = []
        drafts = []
    }

    private func storeDraft(_ context: String, _ tokens: [Int32]) {
        drafts.removeAll { $0.context == context }
        guard !tokens.isEmpty else { return }
        drafts.append((context, tokens))
        if drafts.count > Self.maxDrafts {
            drafts.removeFirst(drafts.count - Self.maxDrafts)
        }
    }

    /// Python `list.sort` is stable; Swift's `sort` is not guaranteed to be.
    static func stableSorted<T>(_ a: [T], by less: (T, T) -> Bool) -> [T] {
        a.enumerated().sorted { x, y in
            if less(x.element, y.element) { return true }
            if less(y.element, x.element) { return false }
            return x.offset < y.offset
        }.map(\.element)
    }

    // MARK: - Chunked conversion

    /// gen_eval --chunk splitting: punctuation-ended parts merged greedily up to `chunk` characters. When the
    /// reading only grows, every group but the last is final (see `GenmaiIncrementalConverter`).
    public static func split(_ reading: String, chunk: Int = 40) -> [String] {
        let u = Array(reading.unicodeScalars)
        if chunk <= 0 || u.count <= chunk { return [reading] }
        let punct: Set<Unicode.Scalar> = ["、", "。", "，", "．", "！", "？", "!", "?"]
        var raw: [[Unicode.Scalar]] = []
        var cur: [Unicode.Scalar] = []
        for c in u {
            cur.append(c)
            if punct.contains(c) {
                raw.append(cur)
                cur = []
            }
        }
        if !cur.isEmpty { raw.append(cur) }
        var parts: [[Unicode.Scalar]] = []
        for p in raw {
            if let last = parts.last, last.count + p.count <= chunk {
                parts[parts.count - 1] += p
            } else {
                parts.append(p)
            }
        }
        return parts.map { String(String.UnicodeScalarView($0)) }
    }

    /// Beam across one chunk: decode `part` after every hypothesis (one batch) and keep the best `beams`.
    public func extend(_ hyps: [GenmaiCandidate], part: String, context: String = "", options: GenmaiOptions = .init())
        throws -> [GenmaiCandidate]
    {
        let outs = try genBatch(part, contexts: hyps.map { context + $0.text },
                                beams: hyps.count == 1 ? options.beams : options.chunkBeams, minRatio: options.minRatio,
                                reusePromptKV: options.reusePromptKV, draft: options.draft,
                                draftMargin: options.draftMargin)
        var nxt: [GenmaiCandidate] = []
        for (h, o) in zip(hyps, outs) {
            for c in o { nxt.append(GenmaiCandidate(text: h.text + c.text, score: h.score + c.score)) }
        }
        nxt = Self.stableSorted(nxt) { $0.score > $1.score }
        var seen = Set<String>()
        var res: [GenmaiCandidate] = []
        for c in nxt where seen.insert(c.text).inserted {
            res.append(c)
        }
        return Array(res.prefix(options.beams))
    }

    /// Converts `reading` (hiragana) after the left `context`; long readings are split at punctuation and the
    /// beam continues across chunks (all hypotheses of a chunk are decoded in one batch). Best first.
    public func convert(_ reading: String, context: String = "", options: GenmaiOptions = .init()) throws
        -> [GenmaiCandidate]
    {
        var hyps = [GenmaiCandidate(text: "", score: 0)]
        for c in Self.split(reading, chunk: options.chunk) {
            hyps = try extend(hyps, part: c, context: context, options: options)
        }
        return hyps
    }
}
