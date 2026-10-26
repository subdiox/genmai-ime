// swift-tools-version: 6.2
// genmai: a Japanese input method for macOS and iOS. The conversion engine is ported from Mozc (https://github.com/google/mozc).
import PackageDescription

let swiftSettings: [SwiftSetting] = [
  .enableUpcomingFeature("ExistentialAny")
]

// Mozc's engine-level directories reference each other (converter ↔ prediction / rewriter / engine,
// data_manager → converter headers, dictionary → request, ...), so they live together in GenmaiCore with one
// subfolder per Mozc directory. Layers: GenmaiBase / GenmaiStorage / GenmaiProtocol → GenmaiCore → GenmaiSession.
let package = Package(
  name: "genmai-ime",
  platforms: [.macOS(.v15), .iOS(.v18)],
  products: [
    .library(name: "GenmaiProtocol", targets: ["GenmaiProtocol"]),
    .library(name: "GenmaiBase", targets: ["GenmaiBase"]),
    .library(name: "GenmaiStorage", targets: ["GenmaiStorage"]),
    .library(name: "GenmaiCore", targets: ["GenmaiCore"]),
    .library(name: "GenmaiSession", targets: ["GenmaiSession"]),
    .executable(name: "genmai-engine", targets: ["genmai-engine"]),
    // Build tools: generates genmai.data / mock_genmai.data from data/ sources (no Bazel).
    .library(name: "GenmaiDataGen", targets: ["GenmaiDataGen"]),
    .executable(name: "genmai-datagen", targets: ["genmai-datagen"]),
    // macOS IME app layer (mac/, renderer/, gui/, client/).
    .library(name: "GenmaiClient", targets: ["GenmaiClient"]),
    .library(name: "GenmaiRenderer", targets: ["GenmaiRenderer"]),
    .library(name: "GenmaiGUI", targets: ["GenmaiGUI"]),
    .library(name: "GenmaiMac", targets: ["GenmaiMac"]),
    .executable(name: "GenmaiIME", targets: ["GenmaiIME"]),
    .executable(name: "GenmaiApp", targets: ["GenmaiApp"]),
    .executable(name: "GenmaiUninstaller", targets: ["GenmaiUninstaller"]),
    // genmai: LLM-based kana-kanji conversion (GPT-2 char-level model on Core ML).
    .library(name: "GenmaiAI", targets: ["GenmaiAI"]),
    .executable(name: "genmai-cli", targets: ["genmai-cli"]),
    // The genmai model as the IME's AI conversion augmenter (GenmaiClient's AIConversionHook).
    .library(name: "GenmaiAIClient", targets: ["GenmaiAIClient"]),
    // iOS: the keyboard logic (ios/ios_engine + its client; also builds and is tested on macOS), the keyboard
    // extension's UI and the app's UI (iOS only; the Xcode project in iOS/ links them).
    .library(name: "GenmaiIOS", targets: ["GenmaiIOS"]),
    .library(name: "GenmaiIOSKeyboard", targets: ["GenmaiIOSKeyboard"]),
    .library(name: "GenmaiIOSApp", targets: ["GenmaiIOSApp"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0")
  ],
  targets: [
    .target(
      name: "GenmaiProtocol",
      dependencies: [.product(name: "SwiftProtobuf", package: "swift-protobuf")],
      exclude: ["README.md"],
      swiftSettings: swiftSettings
    ),
    .target(name: "GenmaiBase", swiftSettings: swiftSettings),
    .target(name: "GenmaiStorage", dependencies: ["GenmaiBase"], swiftSettings: swiftSettings),
    .target(
      name: "GenmaiCore", dependencies: ["GenmaiBase", "GenmaiStorage", "GenmaiProtocol"], swiftSettings: swiftSettings),
    .target(
      name: "GenmaiSession", dependencies: ["GenmaiBase", "GenmaiStorage", "GenmaiProtocol", "GenmaiCore"],
      swiftSettings: swiftSettings),
    // Data set generators (ports of the gen_*.py / gen_*_main.cc build tools) and their CLI.
    .target(
      name: "GenmaiDataGen", dependencies: ["GenmaiBase", "GenmaiStorage", "GenmaiProtocol", "GenmaiCore"],
      swiftSettings: swiftSettings),
    .executableTarget(
      name: "genmai-datagen", dependencies: ["GenmaiDataGen", "GenmaiBase"], swiftSettings: swiftSettings),
    .executableTarget(
      name: "genmai-engine",
      dependencies: ["GenmaiBase", "GenmaiStorage", "GenmaiProtocol", "GenmaiCore", "GenmaiSession"],
      swiftSettings: swiftSettings
    ),
    // IME app layer. GenmaiClient mirrors client/ (ClientInterface + user dictionary storage/importer);
    // GenmaiRenderer mirrors renderer/ (+ renderer/mac with SwiftUI views); GenmaiGUI mirrors gui/ (SwiftUI);
    // GenmaiMac mirrors mac/ (KeyCodeMap, the IMK input controller); GenmaiIME / GenmaiApp are the app entry points.
    .target(
      name: "GenmaiClient",
      dependencies: ["GenmaiBase", "GenmaiProtocol", "GenmaiCore", "GenmaiSession"],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "GenmaiRenderer",
      dependencies: ["GenmaiBase", "GenmaiProtocol", "GenmaiClient"],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "GenmaiGUI",
      dependencies: ["GenmaiBase", "GenmaiProtocol", "GenmaiCore", "GenmaiSession", "GenmaiClient"],
      swiftSettings: swiftSettings
    ),
    .target(name: "GenmaiMacObjC", path: "Sources/GenmaiMacObjC"),
    .target(
      name: "GenmaiMac",
      dependencies: ["GenmaiBase", "GenmaiProtocol", "GenmaiCore", "GenmaiClient", "GenmaiRenderer", "GenmaiMacObjC"],
      swiftSettings: swiftSettings,
      linkerSettings: [.linkedFramework("InputMethodKit"), .linkedFramework("Carbon")]
    ),
    .executableTarget(
      name: "GenmaiIME",
      dependencies: [
        "GenmaiMac", "GenmaiClient", "GenmaiRenderer", "GenmaiBase", "GenmaiCore", "GenmaiProtocol", "GenmaiAIClient",
      ],
      swiftSettings: swiftSettings
    ),
    .executableTarget(
      name: "GenmaiApp",
      dependencies: ["GenmaiGUI", "GenmaiClient", "GenmaiBase"],
      swiftSettings: swiftSettings
    ),
    // mac/Uninstaller: the SwiftUI uninstaller app (bundle: Tools/make_uninstaller_bundle.sh).
    .executableTarget(
      name: "GenmaiUninstaller",
      dependencies: ["GenmaiBase"],
      swiftSettings: swiftSettings
    ),
    // genmai AI converter (GPT-2 on Core ML). Independent of the conversion engine.
    .target(name: "GenmaiAI", swiftSettings: swiftSettings),
    // AI conversion in the IME: GenmaiAugmenter (ConversionAugmenter of GenmaiClient's AIConversionHook).
    .target(name: "GenmaiAIClient", dependencies: ["GenmaiAI", "GenmaiClient"], swiftSettings: swiftSettings),
    .target(
      name: "GenmaiIOS",
      dependencies: ["GenmaiBase", "GenmaiProtocol", "GenmaiCore", "GenmaiSession", "GenmaiClient"],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "GenmaiIOSKeyboard",
      dependencies: ["GenmaiIOS", "GenmaiAIClient", "GenmaiClient", "GenmaiBase", "GenmaiProtocol", "GenmaiCore"],
      resources: [.process("Resources")],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "GenmaiIOSApp",
      dependencies: ["GenmaiIOS", "GenmaiGUI", "GenmaiClient", "GenmaiBase", "GenmaiProtocol", "GenmaiCore"],
      swiftSettings: swiftSettings
    ),
    .executableTarget(
      name: "genmai-cli",
      dependencies: ["GenmaiAI", "GenmaiAIClient", "GenmaiClient", "GenmaiCore", "GenmaiBase", "GenmaiProtocol"],
      swiftSettings: swiftSettings
    ),
    .testTarget(name: "GenmaiAITests", dependencies: ["GenmaiAI"], swiftSettings: swiftSettings),
    .testTarget(
      name: "GenmaiAIClientTests",
      dependencies: ["GenmaiAIClient", "GenmaiAI", "GenmaiClient", "GenmaiCore", "GenmaiBase", "GenmaiProtocol"],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "GenmaiClientTests",
      dependencies: ["GenmaiClient", "GenmaiProtocol", "GenmaiBase", "GenmaiCore", "GenmaiSession"],
      swiftSettings: swiftSettings),
    .testTarget(
      name: "GenmaiRendererTests", dependencies: ["GenmaiRenderer", "GenmaiProtocol"], swiftSettings: swiftSettings),
    .testTarget(
      name: "GenmaiGUITests",
      dependencies: ["GenmaiGUI", "GenmaiClient", "GenmaiProtocol", "GenmaiCore", "GenmaiBase"],
      swiftSettings: swiftSettings),
    .testTarget(
      name: "GenmaiMacTests",
      dependencies: [
        "GenmaiMac", "GenmaiClient", "GenmaiRenderer", "GenmaiProtocol", "GenmaiBase", "GenmaiCore", "GenmaiSession",
      ], swiftSettings: swiftSettings),
    .testTarget(
      name: "GenmaiUninstallerTests", dependencies: ["GenmaiUninstaller", "GenmaiBase"], swiftSettings: swiftSettings),
    .testTarget(
      name: "GenmaiIOSTests",
      dependencies: ["GenmaiIOS", "GenmaiClient", "GenmaiProtocol", "GenmaiBase", "GenmaiCore"],
      swiftSettings: swiftSettings),
    .testTarget(name: "GenmaiProtocolTests", dependencies: ["GenmaiProtocol"], swiftSettings: swiftSettings),
    .testTarget(name: "GenmaiBaseTests", dependencies: ["GenmaiBase"], swiftSettings: swiftSettings),
    .testTarget(
      name: "GenmaiStorageTests", dependencies: ["GenmaiStorage", "GenmaiBase"], swiftSettings: swiftSettings),
    .testTarget(
      name: "GenmaiCoreTests", dependencies: ["GenmaiCore", "GenmaiBase", "GenmaiStorage", "GenmaiProtocol"],
      swiftSettings: swiftSettings),
    .testTarget(
      name: "GenmaiSessionTests", dependencies: ["GenmaiSession", "GenmaiCore", "GenmaiBase", "GenmaiProtocol"],
      swiftSettings: swiftSettings),
    .testTarget(
      name: "GenmaiDataGenTests",
      dependencies: ["GenmaiDataGen", "GenmaiCore", "GenmaiBase", "GenmaiStorage", "GenmaiProtocol"],
      swiftSettings: swiftSettings),
  ]
)
