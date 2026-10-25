// Types shared by the genmai decoder, converter and their clients.

import Foundation

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

  public init(
    beams: Int = 5, chunk: Int = 40, chunkBeams: Int = 4, minRatio: Double = 0, reusePromptKV: Bool = true,
    draft: Bool = false, draftMargin: Float = 2
  ) {
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
    case nLayer = "n_layer"
    case nEmbd = "n_embd"
    case nHead = "n_head"
    case layerNormEpsilon = "layer_norm_epsilon"
    case vocabSize = "vocab_size"
    case nPositions = "n_positions"
    case promptFormat = "genmai_prompt_format"
  }
}
