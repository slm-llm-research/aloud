import Foundation

public protocol CleanupLLM: Sendable {
    var name: String { get }
    func complete(system: String, user: String, timeout: TimeInterval) async throws -> String
}

public enum LLMError: Error, Equatable {
    case http(Int, String)
    case badResponse
    /// Stopped at the token cap: the text is missing its end (BUG-001 H2).
    case truncated
}

/// Room for the rewrite plus reasoning: about 1.5 tokens out per 4 characters in, never below `floor`.
func outputTokenCap(for user: String, floor: Int) -> Int {
    min(8_192, max(floor, user.utf8.count * 3 / 8 + 600))
}

/// OpenAI-compatible chat completions (Groq). M0 winner: `openai/gpt-oss-120b`, reasoning low:
/// 100% rule pass, 254 ms p50 / 571 ms p95.
public struct OpenAICompatibleLLM: CleanupLLM {
    public let name: String
    let baseURL: URL
    let apiKey: String
    let model: String
    let extra: [String: String]
    let session: URLSession

    public init(name: String, baseURL: URL, apiKey: String, model: String, extra: [String: String] = [:],
                session: URLSession = .shared) {
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.extra = extra
        self.session = session
    }

    public static func groq(apiKey: String) -> OpenAICompatibleLLM {
        OpenAICompatibleLLM(name: "groq", baseURL: URL(string: "https://api.groq.com/openai/v1")!,
                            apiKey: apiKey, model: "openai/gpt-oss-120b", extra: ["reasoning_effort": "low"])
    }

    func makeRequest(system: String, user: String, timeout: TimeInterval) throws -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent("chat/completions"), timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": model, "temperature": 0, "max_tokens": outputTokenCap(for: user, floor: 1200),
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ]
        for (k, v) in extra { body[k] = v }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    static func parse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else { throw LLMError.badResponse }
        if choices.first?["finish_reason"] as? String == "length" { throw LLMError.truncated }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func complete(system: String, user: String, timeout: TimeInterval) async throws -> String {
        let (data, resp) = try await session.data(for: makeRequest(system: system, user: user, timeout: timeout))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw LLMError.http(code, String(decoding: data.prefix(300), as: UTF8.self)) }
        return try Self.parse(data)
    }
}

/// Anthropic Messages API over raw HTTP (there is no official Swift SDK). Claude Haiku 5.5 with
/// thinking off and low effort; the system prompt is marked cacheable. M0: 100% pass, 768 ms p50.
public struct AnthropicLLM: CleanupLLM {
    public let name = "haiku"
    let apiKey: String
    let model: String
    let session: URLSession

    public init(apiKey: String, model: String = "claude-haiku-5-5", session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func makeRequest(system: String, user: String, timeout: TimeInterval) throws -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": model, "max_tokens": outputTokenCap(for: user, floor: 1024),
            "system": [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]],
            "thinking": ["type": "disabled"],
            "output_config": ["effort": "low"],
            "messages": [["role": "user", "content": user]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    static func parse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]]
        else { throw LLMError.badResponse }
        if json["stop_reason"] as? String == "refusal" { throw LLMError.badResponse }
        if json["stop_reason"] as? String == "max_tokens" { throw LLMError.truncated }
        let text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func complete(system: String, user: String, timeout: TimeInterval) async throws -> String {
        let (data, resp) = try await session.data(for: makeRequest(system: system, user: user, timeout: timeout))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw LLMError.http(code, String(decoding: data.prefix(300), as: UTF8.self)) }
        return try Self.parse(data)
    }
}
