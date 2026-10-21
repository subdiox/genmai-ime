# genmai

**genmai** (玄米, brown rice) is a Japanese input method for macOS that combines a classic dictionary-based
conversion engine with an on-device language model. While you type, a small kana-kanji conversion model
(genmai, 310M parameters, running on the GPU with [MLX](https://github.com/ml-explore/mlx-swift)) converts the
whole sentence in the background; its result is shown first in the suggestion window and on the conversion key.
Nothing you type leaves your Mac.

> Status: experimental. It is usable day to day, but expect rough edges.

## Features

- **AI conversion (optional, on device).** The genmai model reads the left context (up to 500 characters of the
  text before the cursor) and the reading and decodes the conversion by beam search. Conversion of each keystroke
  starts immediately (speculative decoding with KV-cache reuse and draft-and-verify), so the result is usually
  ready when you press the conversion key.
- **A complete conversion engine in Swift.** The engine, all rewriters, prediction and learning, the composer,
  key handling, the user dictionary and the data set generators are a faithful Swift port of
  [Mozc](https://github.com/google/mozc) 3.35.6354, verified against the C++ implementation (see *Parity*).
  With AI conversion off, genmai converts exactly like Mozc.
- **Native macOS UI.** InputMethodKit, SwiftUI candidate window, settings, dictionary tool and word registration.

### Accuracy

Strict top-1 accuracy through the IME session layer (`genmai-cli session-eval`, M4 Pro, typing at 120 ms per kana):

| | AJIMEE-Bench (200) | everyday sentences (101) |
|---|---|---|
| engine alone (AI off) | 51.5 % | 72.3 % |
| with AI conversion | 90.5 % | 92.1 % |

Conversion-key latency with AI conversion: median 9–16 ms when the key follows the last kana by one typing
interval, 43–66 ms when it is pressed right after it.

## Requirements

- macOS 15 or later, Apple silicon (AI conversion uses Metal through MLX)
- Xcode 26 or later (Swift 6.2 toolchain with the Metal toolchain installed)
- ~1 GB of disk for the AI model

## Build and install

```sh
git clone https://github.com/subdiox/genmai-ime.git
cd genmai-ime
git submodule update --init --depth 1      # Vendor/mozc (dictionary sources)
Tools/make_ime_bundle.sh --build-data      # builds Data/genmai.data and build/Genmai.app
build/Genmai.app/Contents/MacOS/GenmaiIME --self_test
```

Install it either with the installer package (`Tools/make_installer_pkg.sh` → `build/Genmai.pkg`, installs into
`/Library/Input Methods`) or by hand:

```sh
cp -R build/Genmai.app ~/Library/Input\ Methods/
~/Library/Input\ Methods/Genmai.app/Contents/MacOS/GenmaiIME --register_input_source
```

Then add **Genmai** in System Settings › Keyboard › Input Sources (log out and in if it does not appear).
Settings and learning data live in `~/Library/Application Support/Genmai`.

### AI conversion

The model is not part of the app. Download and convert it once (1.2 GB download, 0.6 GB on disk):

```sh
Tools/prepare_genmai_model.sh      # from Hugging Face: subdiox/genmai-v25m-kd
```

Then turn on **Use AI conversion** in the settings (tab "AI"). The settings are stored in
`~/Library/Application Support/Genmai/ai_conversion.json`.

## Repository layout

| path | contents |
|---|---|
| `Sources/GenmaiBase`, `GenmaiStorage`, `GenmaiProtocol` | utilities, storage formats, protobuf messages |
| `Sources/GenmaiCore` | conversion engine: dictionary, converter, rewriters, prediction, composer, engine |
| `Sources/GenmaiSession` | key handling and sessions |
| `Sources/GenmaiDataGen`, `genmai-datagen` | builds the data set (`Data/genmai.data`) from the dictionary sources |
| `Sources/GenmaiAI`, `genmai-cli` | the genmai model on MLX (tokenizer, prompt, decoder) and its CLI |
| `Sources/GenmaiClient`, `GenmaiAIClient` | client layer and the AI conversion hook |
| `Sources/GenmaiMac`, `GenmaiRenderer`, `GenmaiGUI`, `GenmaiIME`, `GenmaiTool`, `GenmaiUninstaller` | the macOS app |
| `Vendor/mozc` | upstream Mozc (git submodule): dictionary sources and the reference implementation for parity tests |
| `Tools/` | build, bundle, installer and parity scripts |

`PORTING_STATUS.md` lists every upstream C++ file and its state in this port.

## Development

```sh
swift build
swift test                       # ~2,100 tests; model-backed tests are skipped without the AI model
```

### Parity

The C++ Mozc in `Vendor/mozc` is the reference. `Tools/build_oracle.sh` builds its tools with Bazel, and the
fixtures in `Tests/Fixtures/oracle`, `Tests/Fixtures/session` and `Tests/Fixtures/quality_regression` are
compared in the tests: conversion 734/734 inputs (lattice and candidates), prediction 200/200 (desktop and
mobile), 79/79 session scenario files, the 680-case evaluation set, and byte-identical data sets.

### Evaluation

`genmai-cli session-eval [--typing-ms N] [--errors] <set.json>` types readings through the session layer with and
without AI conversion and reports accuracy and latency (see `CLAUDE.md`).

## License and acknowledgments

- genmai-ime is released under the BSD 3-Clause License (`LICENSE`). The conversion engine, data generators and
  parts of the UI are ported from [Mozc](https://github.com/google/mozc), Copyright Google Inc., BSD 3-Clause.
- The dictionary data built into `genmai.data` contains data derived from IPAdic (NAIST; see `LICENSE`), the
  [Japanese usage dictionary](https://github.com/hiroyuki-komatsu/japanese-usage-dictionary) (BSD 2-Clause)
  and Japan Post zip code data. Build scripts download the latter two at pinned versions.
- The AI model [subdiox/genmai-v25m-kd](https://huggingface.co/subdiox/genmai-v25m-kd) is distributed separately
  under CC BY-SA 4.0. It is fine-tuned from [zenz-v2.5-medium](https://huggingface.co/Miwa-Keita/zenz-v2.5-medium)
  by Miwa-Keita (CC BY-SA 4.0).
- Uses [mlx-swift](https://github.com/ml-explore/mlx-swift) (MIT) and
  [swift-protobuf](https://github.com/apple/swift-protobuf) (Apache 2.0).
- genmai is not affiliated with or endorsed by Google.
