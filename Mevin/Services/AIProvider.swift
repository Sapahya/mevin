import Foundation

/// The two providers Mevin talks to. Vision is OpenAI only; DeepSeek is text.
enum AIProvider: String, CaseIterable, Identifiable {
    case openai
    case deepseek

    var id: String { rawValue }

    /// Keychain account name. Stable; do not rename.
    var account: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .deepseek: return "DeepSeek"
        }
    }

    var supportsVision: Bool { self == .openai }

    /// Change these in one place when a provider retires a model name.
    static var openaiVisionModel = "gpt-4o"
    static var openaiKeyCheckModel = "gpt-4o-mini"
    static var openaiKeyCheckURL = URL(string: "https://api.openai.com/v1/models")!
    static var deepseekTextModel = "deepseek-chat"
    static var deepseekKeyCheckURL = URL(string: "https://api.deepseek.com/v1/models")!
    static var openaiChatURL = URL(string: "https://api.openai.com/v1/chat/completions")!

    var keyCheckURL: URL {
        switch self {
        case .openai: return Self.openaiKeyCheckURL
        case .deepseek: return Self.deepseekKeyCheckURL
        }
    }

    /// One cheap request so a bad key is reported at save time, not at first use.
    /// The key itself is never included in the returned error.
    static func validate(_ key: String, provider: AIProvider) async -> Bool {
        var request = URLRequest(url: provider.keyCheckURL, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (200..<300).contains(status)
        } catch {
            return false
        }
    }
}

enum AIKeyStatus: String {
    case notSet
    case saved
    case rejected

    var line: String {
        switch self {
        case .notSet: return "Not set"
        case .saved: return "Saved"
        case .rejected: return "Saved, key rejected"
        }
    }
}
