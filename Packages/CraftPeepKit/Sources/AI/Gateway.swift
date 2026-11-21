import Domain
import Foundation
import Security

// MARK: - Secrets

/// Where API keys live. Never a file, never a log, never an export.
public protocol SecretStore: Sendable {
    func secret(for account: String) throws -> String?
    func setSecret(_ secret: String?, for account: String) throws
}

public struct KeychainSecretStore: SecretStore {
    private let service: String

    public init(service: String = "CraftPeep AI") {
        self.service = service
    }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func secret(for account: String) throws -> String? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError(status: status) }
        return String(data: data, encoding: .utf8)
    }

    public func setSecret(_ secret: String?, for account: String) throws {
        let deleted = SecItemDelete(query(account) as CFDictionary)
        guard deleted == errSecSuccess || deleted == errSecItemNotFound else { throw KeychainError(status: deleted) }
        guard let secret, !secret.isEmpty else { return }
        var attributes = query(account)
        attributes[kSecValueData as String] = Data(secret.utf8)
        let added = SecItemAdd(attributes as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError(status: added) }
    }

    public struct KeychainError: Error, CustomStringConvertible {
        let status: OSStatus
        public var description: String { "Keychain error \(status)" }
    }
}

/// For tests and previews.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    public init() {}

    public func secret(for account: String) throws -> String? {
        lock.withLock { values[account] }
    }

    public func setSecret(_ secret: String?, for account: String) throws {
        lock.withLock { values[account] = secret }
    }
}

// MARK: - Prices

/// Published prices for estimating cost, in US dollars per million tokens. A model not listed here has
/// no estimate: its cost is shown as unknown, never as zero. Checked 3 November 2026.
public enum Pricing {
    static let table: [(prefix: String, input: Double, output: Double)] = [
        ("claude-fable-5-2", 8, 40), ("claude-fable-5", 10, 50),
        ("claude-opus-5-5", 4, 20), ("claude-opus-5", 5, 25), ("claude-opus-4", 5, 25),
        ("claude-sonnet-5", 2, 10), ("claude-sonnet-4-6", 3, 15),
        ("claude-haiku-5-5", 0.10, 0.50), ("claude-haiku-4-5", 1, 5)
    ]

    public static func estimateMicros(model: String, inputTokens: Int?, outputTokens: Int?, isLocal: Bool) -> Int? {
        if isLocal { return 0 }
        guard let price = table.first(where: { model.hasPrefix($0.prefix) }),
              let inputTokens, let outputTokens else { return nil }
        // Dollars per million tokens equals millionths of a dollar per token.
        return Int((Double(inputTokens) * price.input + Double(outputTokens) * price.output).rounded())
    }
}

// MARK: - Gateway

/// What the user chose in Settings. Read fresh for every call, so a change takes effect at once.
public struct AISettings: Sendable, Equatable {
    public var isEnabled: Bool
    public var provider: ProviderConfiguration
    /// Tokens (input plus output) allowed per local day. Zero means no limit.
    public var dailyTokenBudget: Int

    public init(isEnabled: Bool, provider: ProviderConfiguration, dailyTokenBudget: Int) {
        self.isEnabled = isEnabled
        self.provider = provider
        self.dailyTokenBudget = dailyTokenBudget
    }
}

/// Every AI call goes through here: it checks that AI is on and within budget, builds the provider,
/// retries once when that is sensible, and writes the usage ledger. Features never talk to a provider directly.
public struct AIGateway: Sendable {
    private let settings: @Sendable () -> AISettings
    private let secrets: any SecretStore
    private let usage: any AIUsageRepository
    private let transport: any AITransport
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async -> Void

    public init(
        settings: @escaping @Sendable () -> AISettings,
        secrets: any SecretStore,
        usage: any AIUsageRepository,
        transport: any AITransport = URLSessionAITransport(),
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.settings = settings
        self.secrets = secrets
        self.usage = usage
        self.transport = transport
        self.now = now
        self.sleep = sleep
    }

    public var isEnabled: Bool { settings().isEnabled }

    /// The provider currently chosen, for labelling what it writes.
    public var providerName: String { settings().provider.kind.rawValue }

    public static func keyAccount(for kind: ProviderKind) -> String { kind.rawValue }

    public func complete(_ request: AIRequest) async throws -> AIResponse {
        let current = settings()
        guard current.isEnabled else { throw ProviderError.notConfigured }
        let configuration = current.provider
        let provider = try makeProvider(configuration)

        func log(_ outcome: AIUsageRecord.Outcome, _ response: AIResponse? = nil) async {
            try? await usage.record(AIUsageRecord(
                at: now(), feature: request.feature.rawValue, provider: configuration.kind.rawValue,
                model: response?.model ?? configuration.model,
                inputTokens: response?.inputTokens, outputTokens: response?.outputTokens,
                estimatedCostMicros: response.flatMap {
                    Pricing.estimateMicros(model: $0.model, inputTokens: $0.inputTokens, outputTokens: $0.outputTokens, isLocal: configuration.isLocal)
                },
                outcome: outcome
            ))
        }

        if current.dailyTokenBudget > 0 {
            let startOfDay = Calendar.current.startOfDay(for: now())
            if try await usage.totals(since: startOfDay).tokens >= current.dailyTokenBudget {
                await log(.budgetBlocked)
                throw ProviderError.budgetExceeded
            }
        }

        do {
            let response: AIResponse
            do {
                response = try await provider.complete(request)
            } catch let error as ProviderError where error.isRetryable {
                // One more try after a short wait. Longer waits are the user's call, not a background loop's.
                var wait = 2
                if case .rateLimited(let seconds) = error, let seconds {
                    guard seconds <= 20 else { throw error }
                    wait = max(1, seconds)
                }
                await sleep(.seconds(wait))
                response = try await provider.complete(request)
            }
            await log(.ok, response)
            return response
        } catch {
            await log(.error)
            throw error
        }
    }

    private func makeProvider(_ configuration: ProviderConfiguration) throws -> any AIProvider {
        let key: String?
        do {
            key = try secrets.secret(for: Self.keyAccount(for: configuration.kind))
        } catch {
            throw ProviderError.missingKey
        }
        switch configuration.kind {
        case .anthropic:
            guard let key, !key.isEmpty else { throw ProviderError.missingKey }
            return try AnthropicProvider(model: configuration.model, apiKey: key, transport: transport)
        case .openAICompatible:
            // A local server needs no key; a remote one does.
            if !configuration.isLocal, key?.isEmpty != false { throw ProviderError.missingKey }
            return try OpenAICompatibleProvider(baseURL: configuration.baseURL, model: configuration.model, apiKey: key, transport: transport)
        }
    }
}
