import Foundation

/// Claude through the Messages API, over plain HTTPS. There is no official Swift SDK.
public struct AnthropicProvider: AIProvider {
    static let apiVersion = "2026-10-21"
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    private let model: String
    private let apiKey: String
    private let transport: any AITransport
    private let endpoint: URL

    public init(model: String, apiKey: String, transport: any AITransport, baseURL: String = ProviderConfiguration.anthropicBaseURL) throws {
        guard let endpoint = URL(string: baseURL)?.appending(path: "v1/messages") else { throw ProviderError.notConfigured }
        self.model = model
        self.apiKey = apiKey
        self.transport = transport
        self.endpoint = endpoint
    }

    /// Models that take `output_config.effort`. Sending it to one that does not is a 400.
    static func supportsEffort(_ model: String) -> Bool {
        ["claude-fable", "claude-mythos", "claude-opus-5", "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6",
         "claude-sonnet-5", "claude-sonnet-4-6", "claude-haiku-5"].contains { model.hasPrefix($0) }
    }

    /// Models whose safety classifiers can decline a request, and which can hand it to another model
    /// inside the same call when asked to.
    static func supportsServerFallback(_ model: String) -> Bool {
        ["claude-fable-5-1", "claude-fable-5-2", "claude-opus-5", "claude-sonnet-5-5"].contains { model.hasPrefix($0) }
    }

    func body(for request: AIRequest) -> JSON {
        var outputConfig: [String: JSON] = [:]
        if Self.supportsEffort(model) {
            outputConfig["effort"] = .string(request.effort.rawValue)
        }
        if let schema = request.schema {
            outputConfig["format"] = .object(["type": .string("json_schema"), "schema": schema])
        }

        var body: [String: JSON] = [
            "model": .string(model),
            "max_tokens": .number(Double(request.maxOutputTokens)),
            // Instructions first and marked cacheable; the story data that varies comes after.
            "system": .array([.object([
                "type": .string("text"),
                "text": .string(request.system),
                "cache_control": .object(["type": .string("ephemeral")])
            ])]),
            "messages": .array([.object(["role": .string("user"), "content": .string(request.user)])])
        ]
        if !outputConfig.isEmpty { body["output_config"] = .object(outputConfig) }
        if Self.supportsServerFallback(model) { body["fallbacks"] = .string("default") }
        return .object(body)
    }

    public func complete(_ request: AIRequest) async throws -> AIResponse {
        var headers = [
            "Content-Type": "application/json",
            "x-api-key": apiKey,
            "anthropic-version": Self.apiVersion
        ]
        if Self.supportsServerFallback(model) { headers["anthropic-beta"] = Self.fallbackBeta }

        let reply = try await transport.post(
            endpoint, headers: headers, body: try JSONEncoder().encode(body(for: request)), timeout: 180
        )
        guard reply.status == 200 else { throw Self.error(for: reply, model: model) }
        guard let json = try? JSONDecoder().decode(JSON.self, from: reply.body) else {
            throw ProviderError.invalidResponse("not JSON")
        }

        // Check why the model stopped before trusting what it wrote.
        switch json["stop_reason"]?.string {
        case "refusal": throw ProviderError.refused
        case "max_tokens": throw ProviderError.truncated
        default: break
        }

        let text = (json["content"]?.array ?? [])
            .filter { $0["type"]?.string == "text" }
            .compactMap { $0["text"]?.string }
            .joined()
        guard !text.isEmpty else { throw ProviderError.invalidResponse("no text in reply") }

        let usage = json["usage"]
        let input = [usage?["input_tokens"]?.int, usage?["cache_read_input_tokens"]?.int, usage?["cache_creation_input_tokens"]?.int]
            .compactMap { $0 }
        return AIResponse(
            text: text,
            model: json["model"]?.string ?? model,
            inputTokens: input.isEmpty ? nil : input.reduce(0, +),
            outputTokens: usage?["output_tokens"]?.int
        )
    }

    static func error(for reply: HTTPReply, model: String) -> ProviderError {
        let json = try? JSONDecoder().decode(JSON.self, from: reply.body)
        let message = String((json?["error"]?["message"]?.string ?? "HTTP \(reply.status)").prefix(200))
        switch reply.status {
        case 401, 403: return .unauthorised
        case 404: return .modelNotFound(model)
        case 429: return .rateLimited(retryAfterSeconds: reply.header("retry-after").flatMap { Int($0) })
        case 500...599: return .overloaded
        default: return .badRequest(message)
        }
    }
}

/// Any server that speaks the OpenAI chat completions protocol: OpenAI itself, Ollama, LM Studio, OpenRouter.
public struct OpenAICompatibleProvider: AIProvider {
    private let model: String
    private let apiKey: String?
    private let transport: any AITransport
    private let endpoint: URL
    private let isOpenAI: Bool

    public init(baseURL: String, model: String, apiKey: String?, transport: any AITransport) throws {
        guard let base = URL(string: baseURL.trimmingCharacters(in: .whitespaces)), base.host() != nil else {
            throw ProviderError.notConfigured
        }
        guard AITransportPolicy.isAllowed(base) else { throw ProviderError.insecureEndpoint }
        self.model = model
        self.apiKey = apiKey?.isEmpty == false ? apiKey : nil
        self.transport = transport
        endpoint = base.appending(path: "chat/completions")
        isOpenAI = base.host()?.lowercased().hasSuffix("openai.com") == true
    }

    func body(for request: AIRequest, structured: Bool) -> JSON {
        var system = request.system
        if request.schema != nil {
            // Not every compatible server enforces a schema, so the instruction is always in the prompt too.
            system += "\n\nReply with a single JSON object and nothing else."
        }
        var body: [String: JSON] = [
            "model": .string(model),
            "messages": .array([
                .object(["role": .string("system"), "content": .string(system)]),
                .object(["role": .string("user"), "content": .string(request.user)])
            ]),
            // OpenAI's newer models only accept the newer name; local servers only know the older one.
            (isOpenAI ? "max_completion_tokens" : "max_tokens"): .number(Double(request.maxOutputTokens))
        ]
        if structured, let schema = request.schema {
            body["response_format"] = .object([
                "type": .string("json_schema"),
                "json_schema": .object(["name": .string("reply"), "strict": .bool(true), "schema": schema])
            ])
        }
        return .object(body)
    }

    public func complete(_ request: AIRequest) async throws -> AIResponse {
        do {
            return try await send(request, structured: request.schema != nil)
        } catch ProviderError.badRequest where request.schema != nil {
            // The server may not support schema-constrained replies. Ask again in plain mode;
            // the caller validates the JSON either way.
            return try await send(request, structured: false)
        }
    }

    private func send(_ request: AIRequest, structured: Bool) async throws -> AIResponse {
        var headers = ["Content-Type": "application/json"]
        if let apiKey { headers["Authorization"] = "Bearer \(apiKey)" }

        let reply = try await transport.post(
            endpoint, headers: headers,
            body: try JSONEncoder().encode(body(for: request, structured: structured)), timeout: 300
        )
        guard reply.status == 200 else { throw Self.error(for: reply, model: model) }
        guard let json = try? JSONDecoder().decode(JSON.self, from: reply.body),
              let choice = json["choices"]?.array?.first else {
            throw ProviderError.invalidResponse("no choices in reply")
        }
        if choice["finish_reason"]?.string == "length" { throw ProviderError.truncated }
        if let refusal = choice["message"]?["refusal"]?.string, !refusal.isEmpty { throw ProviderError.refused }
        guard let text = choice["message"]?["content"]?.string, !text.isEmpty else {
            throw ProviderError.invalidResponse("no text in reply")
        }
        return AIResponse(
            text: text,
            model: json["model"]?.string ?? model,
            inputTokens: json["usage"]?["prompt_tokens"]?.int,
            outputTokens: json["usage"]?["completion_tokens"]?.int
        )
    }

    static func error(for reply: HTTPReply, model: String) -> ProviderError {
        let json = try? JSONDecoder().decode(JSON.self, from: reply.body)
        // OpenAI nests the message; Ollama returns {"error": "text"}.
        let message = String((json?["error"]?["message"]?.string ?? json?["error"]?.string ?? "HTTP \(reply.status)").prefix(200))
        switch reply.status {
        case 401, 403: return .unauthorised
        case 404: return .modelNotFound(model)
        case 429: return .rateLimited(retryAfterSeconds: reply.header("retry-after").flatMap { Int($0) })
        case 500...599: return .overloaded
        default: return .badRequest(message)
        }
    }
}
