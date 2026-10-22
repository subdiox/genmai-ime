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
| with AI conversion (genmai 0.1.0) | 94.0 % | 92.1 % |

Conversion-key latency with AI conversion: median 11–19 ms when the key follows the last kana by one typing
interval, 45–64 ms when it is pressed right after it.

## Requirements

- macOS 15 or later, Apple silicon (AI conversion uses Metal through MLX)
- ~1 GB of disk for the AI model
- To build: Xcode 26 or later (Swift 6.2 toolchain with the Metal toolchain installed)

## Install

Download `Genmai-X.Y.Z.pkg` from the [latest release](https://github.com/subdiox/genmai-ime/releases/latest) and
open it. The package is not signed with a Developer ID yet: if macOS refuses to open it, allow it in System
Settings › Privacy & Security (**Open Anyway**). It installs into `/Library/Input Methods` and selects the input
source; you can also add **Genmai** in System Settings › Keyboard › Input Sources. Settings and learning data live
in `~/Library/Application Support/Genmai`. To uninstall, use **Uninstall Genmai…** in the settings (General); it asks which of your data (AI model,
user dictionary, learning data, settings) to remove as well.

### Updates

Genmai checks GitHub for a new release once a day and shows a notification; clicking it opens the update dialog,
which downloads the package (verified against the SHA-256 GitHub lists) and opens the installer. The settings (tab
"Misc" › Updates) turn the automatic check off, check on request and install the update. The check sends no data
besides the request for the release list.

To make a release, bump `kProductVersion` in `Sources/GenmaiBase/VersionDef.swift`, commit, and push the tag
`vX.Y.Z`: the GitHub Actions workflow `Release` builds the package and creates the GitHub release
(`Tools/make_release.sh --publish` does the same from a Mac).

## Build from source

```sh
git clone https://github.com/subdiox/genmai-ime.git
cd genmai-ime
git submodule update --init --depth 1      # Vendor/mozc (dictionary sources)
Tools/make_ime_bundle.sh --build-data      # builds Data/genmai.data and build/Genmai.app
build/Genmai.app/Contents/MacOS/GenmaiIME --self_test
```

Install it either with the installer package (`Tools/make_installer_pkg.sh` → `build/Genmai.pkg`, installs into
`/Library/Input Methods` and removes a copy in `~/Library/Input Methods`) or by hand:

```sh
cp -R build/Genmai.app ~/Library/Input\ Methods/
~/Library/Input\ Methods/Genmai.app/Contents/MacOS/GenmaiIME --register_input_source
```

Then add **Genmai** in System Settings › Keyboard › Input Sources (log out and in if it does not appear).
Settings and learning data live in `~/Library/Application Support/Genmai`.

### AI conversion

The model is not part of the app. The settings (tab "AI") look up the latest model release on Hugging Face
([subdiox/genmai](https://huggingface.co/subdiox/genmai)) and offer **Download**: it downloads the model (0.34 GB,
8-bit quantized; "High precision" in the same tab picks the bf16 weights, 0.62 GB, practically the same accuracy;
checked against the checksums Hugging Face lists) and installs it into
`~/Library/Application Support/Genmai/model`. When a newer model is released, the same place offers **Update**;
**Remove Model…** deletes it. From the command line:

```sh
Tools/prepare_genmai_model.sh      # = genmai-cli install
```

Then turn on **Use AI conversion** in the same tab. The settings are stored in
`~/Library/Application Support/Genmai/ai_conversion.json`. AI candidates that cannot be read as the input
(e.g. 母は歯痒いらしい for ははははがいたいらしい) are dropped by a check against the dictionary.

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
- The AI model [subdiox/genmai](https://huggingface.co/subdiox/genmai) is distributed separately
  under CC BY-SA 4.0. It is fine-tuned from [zenz-v2.5-medium](https://huggingface.co/Miwa-Keita/zenz-v2.5-medium)
  by Miwa-Keita (CC BY-SA 4.0).
- Uses [mlx-swift](https://github.com/ml-explore/mlx-swift) (MIT) and
  [swift-protobuf](https://github.com/apple/swift-protobuf) (Apache 2.0).
- genmai is not affiliated with or endorsed by Google.
