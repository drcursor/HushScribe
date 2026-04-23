import Foundation
import Hub
import MLXLLM
import MLXLMCommon
import Tokenizers

// MARK: - Downloader / TokenizerLoader bridges for swift-transformers 1.1.x

private struct HubApiDownloader: Downloader, @unchecked Sendable {
    private let api: HubApi

    init() { self.api = HubApi() }

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        try await api.snapshot(
            from: id,
            revision: revision ?? "main",
            matching: patterns,
            progressHandler: progressHandler
        )
    }
}

private struct AutoTokenizerLoader: TokenizerLoader, @unchecked Sendable {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await AutoTokenizer.from(modelFolder: directory)
        return BridgedTokenizer(upstream)
    }
}

private struct BridgedTokenizer: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) { self.upstream = upstream }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

private let sharedDownloader: any Downloader = HubApiDownloader()
private let sharedTokenizerLoader: any TokenizerLoader = AutoTokenizerLoader()

// MARK: - Engine

/// Manages download, lifecycle, and inference for LLM-based summary models.
/// Models are cached in the standard HuggingFace Hub cache (~/.cache/huggingface/hub/).
@Observable
@MainActor
final class LLMSummaryEngine {
    static let shared = LLMSummaryEngine()

    var downloadingModel: SummaryModel? = nil
    var downloadProgress: Double = 0
    var isGenerating: Bool = false
    var generationStatus: String = ""

    private var loadedContainer: (model: SummaryModel, container: ModelContainer)? = nil

    private init() {}

    // MARK: - Model management

    func isModelDownloaded(_ model: SummaryModel) -> Bool {
        guard let repoID = model.hfRepoID else { return false }
        // swift-transformers (used by mlx-swift-lm) caches at ~/Library/Caches/models/<org>/<name>/
        let configPath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("models/\(repoID)/config.json")
        return FileManager.default.fileExists(atPath: configPath.path)
    }

    func downloadModel(_ model: SummaryModel) async {
        guard let repoID = model.hfRepoID else { return }
        downloadingModel = model
        downloadProgress = 0
        defer { downloadingModel = nil; downloadProgress = 0 }

        do {
            let config = ModelConfiguration(id: repoID)
            _ = try await loadModelContainer(
                from: sharedDownloader,
                using: sharedTokenizerLoader,
                configuration: config
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress.fractionCompleted
                }
            }
        } catch {
            print("[LLMSummaryEngine] Download failed: \(error)")
        }
    }

    func removeModel(_ model: SummaryModel) {
        guard let repoID = model.hfRepoID else { return }
        let cachePath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("models/\(repoID)")
        try? FileManager.default.removeItem(at: cachePath)
        if loadedContainer?.model == model { loadedContainer = nil }
    }

    // MARK: - Inference

    static let defaultSystemPrompt = """
    You are a meeting assistant. When given a meeting transcript, produce a concise summary with two sections:

    1. A section called "Highlights" containing short topic-level headlines (not direct quotes) — one bullet per key topic or decision.
    2. A section called "To-Dos" containing action items, each attributed to the speaker responsible, formatted as bold speaker name followed by the task.

    Use markdown. Omit a section entirely if there is nothing to put in it. Output only the summary — no preamble, no explanation.
    """

    func summarize(transcript: String, temperature: Float = 0.3, maxTokens: Int = 4000, systemPrompt: String? = nil) async throws -> (summary: String, thinking: String?) {
        isGenerating = true
        generationStatus = "Loading model…"
        defer { isGenerating = false; generationStatus = "" }

        guard let cached = loadedContainer else {
            throw LLMError.modelNotLoaded
        }

        generationStatus = "Generating summary…"

        let params = GenerateParameters(maxTokens: maxTokens, temperature: temperature)
        let session = ChatSession(
            cached.container,
            instructions: systemPrompt ?? LLMSummaryEngine.defaultSystemPrompt,
            generateParameters: params
        )
        let userMessage = "Please summarize the following meeting transcript:\n\n\(transcript)"
        let raw = try await session.respond(to: userMessage)
        let thinking = Self.extractThinking(raw)
        let summary = Self.stripThinking(raw)
        return (summary: summary, thinking: thinking)
    }

    /// Load (or re-use) a model container for the given model. Downloads if not cached locally.
    func loadContainer(for model: SummaryModel) async throws {
        guard let repoID = model.hfRepoID else { return }
        if let cached = loadedContainer, cached.model == model { return }

        generationStatus = "Loading model…"
        let config = ModelConfiguration(id: repoID)
        let container = try await loadModelContainer(
            from: sharedDownloader,
            using: sharedTokenizerLoader,
            configuration: config
        ) { [weak self] progress in
            Task { @MainActor in
                self?.generationStatus = "Loading… \(Int(progress.fractionCompleted * 100))%"
            }
        }
        loadedContainer = (model: model, container: container)
        generationStatus = ""
    }

    /// Extracts the content of all <think>...</think> blocks, joined by newlines. Returns nil if none.
    private static func extractThinking(_ text: String) -> String? {
        var blocks: [String] = []
        var remaining = text
        while let open = remaining.range(of: "<think>"),
              let close = remaining.range(of: "</think>", range: open.upperBound..<remaining.endIndex) {
            let content = String(remaining[open.upperBound..<close.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty { blocks.append(content) }
            remaining.removeSubrange(open.lowerBound...close.upperBound)
        }
        return blocks.isEmpty ? nil : blocks.joined(separator: "\n\n")
    }

    /// Strips <think>...</think> blocks that Qwen3 and similar models emit before the actual response.
    private static func stripThinking(_ text: String) -> String {
        var result = text
        while let open = result.range(of: "<think>"),
              let close = result.range(of: "</think>", range: open.upperBound..<result.endIndex) {
            result.removeSubrange(open.lowerBound...close.upperBound)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum LLMError: Error {
        case modelNotLoaded
    }
}
