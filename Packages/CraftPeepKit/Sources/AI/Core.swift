import Foundation

/// A JSON value, for request schemas and for reading model output.
public enum JSON: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSON].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            // Whole numbers go out as integers; some servers reject 16000.0 for max_tokens.
            if value.rounded() == value, abs(value) < 1e15 { try container.encode(Int64(value)) } else { try container.encode(value) }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public subscript(key: String) -> JSON? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var int: Int? {
        if case .number(let value) = self, value.rounded() == value { return Int(value) }
        return nil
    }

    public var array: [JSON]? {
        if case .array(let value) = self { return value }
        return nil
    }

    /// Finds the first JSON object in a model's reply. Models asked for JSON sometimes wrap it in prose
    /// or a code fence; this takes the outermost braces and parses what is between them.
    public static func firstObject(in text: String) -> JSON? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return try? JSONDecoder().decode(JSON.self, from: Data(text[start...end].utf8))
    }
}

public enum AIFeature: String, Sendable {
    case summary
    case briefing
    case connectionTest = "connection_test"
    case widgetBuilder = "widget_builder"
}

public enum ProviderKind: String, Sendable, Codable, CaseIterable {
    case anthropic
    case openAICompatible = "openai_compatible"
}

/// Where AI requests go. Chosen by the user; nothing is sent anywhere until this exists.
public struct ProviderConfiguration: Sendable, Equatable {
    public var kind: ProviderKind
    /// Base URL of the API. Fixed for Anthropic; user-supplied for compatible endpoints.
    public var baseURL: String
    public var model: String

    public init(kind: ProviderKind, baseURL: String, model: String) {
        self.kind = kind
        self.baseURL = baseURL
        self.model = model
    }

    public static let anthropicBaseURL = "https://api.anthropic.com"
    public static let defaultAnthropicModel = "claude-opus-5-5"
    /// Ollama's OpenAI-compatible endpoint on this Mac.
    public static let defaultCompatibleBaseURL = "http://localhost:11434/v1"

    /// True when requests stay on this machine.
    public var isLocal: Bool {
        guard let host = URL(string: baseURL)?.host()?.lowercased() else { return false }
        return AITransportPolicy.isLoopback(host)
    }
}

public struct AIRequest: Sendable, Equatable {
    public enum Effort: String, Sendable {
        case low, medium, high
    }

    public var feature: AIFeature
    /// Instructions. Stable across calls so providers can cache it.
    public var system: String
    /// The material to work on. May contain untrusted third-party text.
    public var user: String
    /// When set, the reply must be a JSON object matching this schema.
    public var schema: JSON?
    public var maxOutputTokens: Int
    public var effort: Effort

    public init(feature: AIFeature, system: String, user: String, schema: JSON? = nil, maxOutputTokens: Int = 16_000, effort: Effort = .medium) {
        self.feature = feature
        self.system = system
        self.user = user
        self.schema = schema
        self.maxOutputTokens = maxOutputTokens
        self.effort = effort
    }
}

public struct AIResponse: Sendable, Equatable {
    public var text: String
    /// The model that actually answered, as the provider reports it.
    public var model: String
    public var inputTokens: Int?
    public var outputTokens: Int?

    public init(text: String, model: String, inputTokens: Int?, outputTokens: Int?) {
        self.text = text
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public enum ProviderError: Error, Equatable, Sendable, CustomStringConvertible {
    case notConfigured
    case missingKey
    case unauthorised
    case rateLimited(retryAfterSeconds: Int?)
    case overloaded
    case badRequest(String)
    case modelNotFound(String)
    /// The provider declined to answer.
    case refused
    /// The reply was cut off at the output limit.
    case truncated
    case invalidResponse(String)
    case network(String)
    case insecureEndpoint
    case budgetExceeded

    public var description: String {
        switch self {
        case .notConfigured: "AI is not set up."
        case .missingKey: "No API key is saved for this provider."
        case .unauthorised: "The provider rejected the API key."
        case .rateLimited(let seconds): "The provider is rate limiting requests" + (seconds.map { "; try again in \($0) seconds." } ?? ".")
        case .overloaded: "The provider is temporarily unavailable."
        case .badRequest(let detail): "The provider rejected the request: \(detail)"
        case .modelNotFound(let model): "The provider does not offer the model “\(model)”."
        case .refused: "The model declined to answer."
        case .truncated: "The reply was cut off before it finished."
        case .invalidResponse(let detail): "The reply could not be used: \(detail)"
        case .network(let detail): "Network error: \(detail)"
        case .insecureEndpoint: "Only https endpoints are allowed, except on this Mac."
        case .budgetExceeded: "Today’s AI budget is used up."
        }
    }

    /// Worth one more attempt after a pause.
    var isRetryable: Bool {
        switch self {
        case .rateLimited, .overloaded, .network: true
        default: false
        }
    }
}

public protocol AIProvider: Sendable {
    func complete(_ request: AIRequest) async throws -> AIResponse
}

// MARK: - Transport

public struct HTTPReply: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    func header(_ name: String) -> String? {
        headers.first { $0.key.lowercased() == name.lowercased() }?.value
    }
}

/// The one way AI code touches the network, so tests can replace it.
public protocol AITransport: Sendable {
    func post(_ url: URL, headers: [String: String], body: Data, timeout: TimeInterval) async throws -> HTTPReply
}

public enum AITransportPolicy {
    public static func isLoopback(_ host: String) -> Bool {
        ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())
    }

    /// https anywhere; plain http only to this machine, where a local model server listens.
    public static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host() else { return false }
        return scheme == "https" || (scheme == "http" && isLoopback(host))
    }
}

public struct URLSessionAITransport: AITransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    public func post(_ url: URL, headers: [String: String], body: Data, timeout: TimeInterval) async throws -> HTTPReply {
        guard AITransportPolicy.isAllowed(url) else { throw ProviderError.insecureEndpoint }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ProviderError.network("not an HTTP response") }
            var replyHeaders: [String: String] = [:]
            for (name, value) in http.allHeaderFields {
                if let name = name as? String, let value = value as? String { replyHeaders[name] = value }
            }
            return HTTPReply(status: http.statusCode, headers: replyHeaders, body: data)
        } catch let error as ProviderError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // The description only: never the request, so the key cannot reach a log or the screen.
            throw ProviderError.network(error.localizedDescription)
        }
    }
}
