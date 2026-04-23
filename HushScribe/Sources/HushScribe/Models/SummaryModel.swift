import Foundation

/// LLM-based summary models. `.appleNL` is the built-in fallback (no download required).
enum SummaryModel: String, CaseIterable {
    case appleNL      = "appleNL"
    case qwen3_0_6b   = "qwen3_0_6b"
    case gemma3_1b    = "gemma3_1b"
    case gemma4_model = "gemma4"

    var displayName: String {
        switch self {
        case .appleNL:      return "Apple NL (Built-in)"
        case .qwen3_0_6b:   return "Qwen3 0.6B"
        case .gemma3_1b:    return "Gemma 3 1B"
        case .gemma4_model: return "Gemma 4 E4B"
        }
    }

    /// HuggingFace repo ID for MLX-format model. `nil` for built-in.
    var hfRepoID: String? {
        switch self {
        case .appleNL:      return nil
        case .qwen3_0_6b:   return "mlx-community/Qwen3-0.6B-4bit"
        case .gemma3_1b:    return "mlx-community/gemma-3-1b-it-qat-4bit"
        case .gemma4_model: return "mlx-community/gemma-4-e4b-it-4bit"
        }
    }

    var sizeLabel: String {
        switch self {
        case .appleNL:      return ""
        case .qwen3_0_6b:   return "~500 MB"
        case .gemma3_1b:    return "~600 MB"
        case .gemma4_model: return "~800 MB"
        }
    }

    var settingsDescription: String {
        switch self {
        case .appleNL:
            return "Apple's NaturalLanguage framework. Instant, no download. Keyword-based topic extraction."
        case .qwen3_0_6b:
            return "Alibaba Qwen3 0.6B (4-bit quantized). Fast, compact LLM. Runs on Apple Silicon ANE."
        case .gemma3_1b:
            return "Google Gemma 3 1B (4-bit quantized, QAT). Stronger reasoning, slightly larger. Runs on Apple Silicon."
        case .gemma4_model:
            return "Google Gemma 4 E4B (4-bit quantized). Multimodal-capable, instruction-tuned. Runs on Apple Silicon."
        }
    }

    var isBuiltIn: Bool { self == .appleNL }
}
