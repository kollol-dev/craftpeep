import AI
import Foundation

/// The user's AI choices, kept in preferences. The API key is not here: it lives in the Keychain.
nonisolated enum AIPreferences {
    static let enabled = "ai.enabled"
    static let kind = "ai.provider"
    static let anthropicModel = "ai.anthropic.model"
    static let compatibleModel = "ai.compatible.model"
    static let compatibleBaseURL = "ai.compatible.baseURL"
    static let dailyBudget = "ai.dailyTokenBudget"
    static let autoBriefing = "ai.automaticBriefing"

    static let defaultDailyBudget = 200_000

    /// Read fresh on every AI call, from any thread.
    static func current() -> AISettings {
        let defaults = UserDefaults.standard
        let kind = ProviderKind(rawValue: defaults.string(forKey: Self.kind) ?? "") ?? .anthropic
        let provider: ProviderConfiguration
        switch kind {
        case .anthropic:
            provider = ProviderConfiguration(
                kind: .anthropic, baseURL: ProviderConfiguration.anthropicBaseURL,
                model: nonEmpty(defaults.string(forKey: anthropicModel)) ?? ProviderConfiguration.defaultAnthropicModel
            )
        case .openAICompatible:
            provider = ProviderConfiguration(
                kind: .openAICompatible,
                baseURL: nonEmpty(defaults.string(forKey: compatibleBaseURL)) ?? ProviderConfiguration.defaultCompatibleBaseURL,
                model: nonEmpty(defaults.string(forKey: compatibleModel)) ?? ""
            )
        }
        let budget = defaults.object(forKey: dailyBudget) as? Int ?? defaultDailyBudget
        return AISettings(isEnabled: defaults.bool(forKey: enabled), provider: provider, dailyTokenBudget: max(0, budget))
    }

    static var automaticBriefing: Bool {
        UserDefaults.standard.bool(forKey: autoBriefing)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
