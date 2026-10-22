// Concurrency-safe entry points of the genmai converter: `GenmaiConverter` (an actor owning the MLX model) and
// `GenmaiIncrementalConverter` (port of the Python reference `IncrementalConverter`).

import Foundation
import Synchronization

/// The genmai converter. All MLX work happens on this actor (MLX arrays are not Sendable). Loading takes about a
/// second, so create it off the main actor (e.g. in a detached task). Every conversion method checks for task
/// cancellation between decode steps and throws `CancellationError`.
public actor GenmaiConverter {
    /// MLX evaluates on a process-wide default stream that must not be used from two threads at once. Every
    /// converter (there may briefly be two, e.g. while a model is reloaded or in tests) takes this lock around
    /// its MLX work; each operation is synchronous, so the lock is never held across a suspension point.
    static let mlxLock = Mutex(())

    /// Total time spent doing MLX work (inside `mlxLock`) by all converters of the process, and the number of
    /// operations (diagnostics: background cost per keystroke in `genmai-cli session-eval`).
    public struct BusyStats: Sendable, Equatable {
        public var seconds: Double = 0
        public var operations: Int = 0
    }

    private static let busy = Mutex(BusyStats())

    public static var busyStats: BusyStats { busy.withLock { $0 } }

    /// Runs `body` while holding `mlxLock` and adds its duration to `busyStats`.
    static func withMLX<T>(_ body: () throws -> T) rethrows -> T {
        try mlxLock.withLock { _ in
            let start = ContinuousClock.now
            defer {
                let (s, a) = (ContinuousClock.now - start).components
                let d = Double(s) + Double(a) / 1e18
                busy.withLock {
                    $0.seconds += d
                    $0.operations += 1
                }
            }
            return try body()
        }
    }

    private let model: GenmaiModel
    public nonisolated let loadSeconds: Double
    public nonisolated let tokenizer: GenmaiTokenizer

    /// The directory the IME loads the model from: `~/Library/Application Support/Genmai/model`
    /// (installed by the config dialog, `genmai-cli install` or Tools/prepare_genmai_model.sh).
    public static var defaultModelDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Genmai/model", directoryHint: .isDirectory)
    }

    public init(directory: URL = GenmaiConverter.defaultModelDirectory) throws {
        let m = try Self.mlxLock.withLock { _ in try GenmaiModel(directory: directory) }
        model = m
        loadSeconds = m.loadSeconds
        tokenizer = m.tokenizer
    }

    /// Pre-compiles the common decode steps (a few hundred ms) so that the first conversion is fast.
    public func warmup() {
        Self.withMLX { model.warmup() }
    }

    /// Converts `reading` (hiragana) after `context` (left context; the last 500 characters are used).
    /// Returns up to `options.beams` candidates, best first; `score` is the total log-probability.
    public func convert(_ reading: String, context: String = "", options: GenmaiOptions = .init()) throws
        -> [GenmaiCandidate]
    {
        try Self.withMLX { try model.convert(reading, context: context, options: options) }
    }

    /// Diagnostics: see `GenmaiModel.debugLogProbs`.
    public func debugLogProbs(_ reading: String, context: String = "", continuation: [Int32] = []) -> [[Float]] {
        Self.withMLX { model.debugLogProbs(reading, context: context, continuation: continuation) }
    }

    /// Beam across one chunk (see `GenmaiModel.extend`).
    public func extend(_ hyps: [GenmaiCandidate], part: String, context: String = "", options: GenmaiOptions = .init())
        throws -> [GenmaiCandidate]
    {
        try Self.withMLX { try model.extend(hyps, part: part, context: context, options: options) }
    }

    /// One beam search per left context, decoded as one batch (see `GenmaiModel.genBatch`).
    public func genBatch(_ reading: String, contexts: [String], beams: Int = 5, minRatio: Double = 0,
                         reusePromptKV: Bool = true, draft: Bool = false, draftMargin: Float = 2) throws
        -> [[GenmaiCandidate]]
    {
        try Self.withMLX {
            try model.genBatch(reading, contexts: contexts, beams: beams, minRatio: minRatio, reusePromptKV: reusePromptKV,
                               draft: draft, draftMargin: draftMargin)
        }
    }

    /// Output tokens accepted from drafts / decode steps run so far (diagnostics).
    public var draftStats: (accepted: Int, decodeSteps: Int) {
        (model.draftTokensAccepted, model.decodeSteps)
    }

    /// Drops the prompt KV cache and the drafts of the model (tests).
    public func clearPromptCache() {
        Self.withMLX { model.clearPromptCache() }
    }

    /// Prompt tokens prefilled / taken from the prompt KV cache so far (diagnostics).
    public var promptTokenStats: (prefilled: Int, reused: Int) {
        (model.promptTokensPrefilled, model.promptTokensReused)
    }
}

/// Converts finished chunks while the user is still typing, so that the conversion key only has to decode the
/// last chunk. Results are identical to `GenmaiConverter.convert` on the final reading: with left-to-right greedy
/// grouping, every group except the last can no longer change once a later group has started.
///
/// Call `update(_:)` after each keystroke (from a background task; cancel it when the next keystroke arrives —
/// already converted groups are kept) and `convert(_:)` on the conversion key. Edits that change an already
/// converted group drop the cached state from that group on. The left context is fixed per instance (one
/// instance per composition).
public actor GenmaiIncrementalConverter {
    public let converter: GenmaiConverter
    public let context: String
    public let options: GenmaiOptions
    private var groups: [String] = []
    /// states[k] = hypotheses after the first k groups.
    private var states: [[GenmaiCandidate]] = [[GenmaiCandidate(text: "", score: 0)]]
    /// Bumped whenever `groups` / `states` are truncated, so that an `update` resumed after a suspension does not
    /// append a state computed from a stale prefix (actor reentrancy).
    private var generation = 0

    public init(converter: GenmaiConverter, context: String = "", options: GenmaiOptions = .init()) {
        self.converter = converter
        self.context = context
        self.options = options
    }

    /// Number of groups converted so far.
    public var convertedGroups: Int { groups.count }

    private func sync(_ final: [String]) {
        var k = 0
        while k < groups.count && k < final.count && groups[k] == final[k] { k += 1 }
        if k < groups.count {
            groups.removeSubrange(k...)
            states.removeSubrange((k + 1)...)
            generation += 1
        }
    }

    /// Converts every group that is final for this reading and not converted yet; returns the number done.
    @discardableResult
    public func update(_ reading: String) async throws -> Int {
        let all = GenmaiModel.split(reading, chunk: options.chunk)
        let final = Array(all.dropLast())
        sync(final)
        var n = 0
        while groups.count < final.count {
            let k = groups.count
            let g = final[k]
            let gen = generation
            let next = try await converter.extend(states[k], part: g, context: context, options: options)
            // another call may have changed the state while this one was suspended
            guard gen == generation, groups.count == k else { return n }
            states.append(next)
            groups.append(g)
            n += 1
        }
        return n
    }

    /// The conversion of the full `reading` (converts any pending final groups first). `lastGroup` overrides the
    /// options of the last group's search (e.g. draft-and-verify for a speculative conversion while typing; the
    /// final groups always use `options`).
    public func convert(_ reading: String, lastGroup: GenmaiOptions? = nil) async throws -> [GenmaiCandidate] {
        while true {
            try await update(reading)
            let all = GenmaiModel.split(reading, chunk: options.chunk)
            let k = all.count - 1
            guard groups.count == k, Array(all.prefix(k)) == groups else { continue }
            let last = lastGroup ?? options
            // A draft (speculative) search continues only the best hypothesis of the earlier groups: with all of
            // them it decodes beams × beams rows (~1 s for a 40-character chunk after a 500-character context).
            let hyps = last.draft ? Array(states[k].prefix(1)) : states[k]
            return try await converter.extend(hyps, part: all[k], context: context, options: last)
        }
    }
}
