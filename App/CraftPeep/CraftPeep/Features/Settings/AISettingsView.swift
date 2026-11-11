import AI
import Domain
import SwiftUI

struct AISettingsView: View {
    let model: AppModel

    @AppStorage(AIPreferences.enabled) private var enabled = false
    @AppStorage(AIPreferences.kind) private var kindRaw = ProviderKind.anthropic.rawValue
    @AppStorage(AIPreferences.anthropicModel) private var anthropicModel = ProviderConfiguration.defaultAnthropicModel
    @AppStorage(AIPreferences.compatibleModel) private var compatibleModel = ""
    @AppStorage(AIPreferences.compatibleBaseURL) private var compatibleBaseURL = ProviderConfiguration.defaultCompatibleBaseURL
    @AppStorage(AIPreferences.dailyBudget) private var dailyBudget = AIPreferences.defaultDailyBudget
    @AppStorage(AIPreferences.autoBriefing) private var automaticBriefing = false

    @State private var keyEntry = ""
    @State private var keyMessage: String?
    @State private var testResult: String?
    @State private var isTesting = false

    private var kind: ProviderKind { ProviderKind(rawValue: kindRaw) ?? .anthropic }
    private var isLocal: Bool { AIPreferences.current().provider.isLocal }
    private var hasKey: Bool { model.savedKeyKinds.contains(kind) }

    var body: some View {
        Form {
            Section {
                Toggle("Use AI for summaries and the daily briefing", isOn: $enabled)
                Text(disclosure)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Provider") {
                Picker("Service", selection: $kindRaw) {
                    Text("Anthropic (Claude)").tag(ProviderKind.anthropic.rawValue)
                    Text("OpenAI-compatible or local").tag(ProviderKind.openAICompatible.rawValue)
                }
                switch kind {
                case .anthropic:
                    Picker("Model", selection: $anthropicModel) {
                        Text("Claude Opus 5.5").tag("claude-opus-5-5")
                        Text("Claude Sonnet 5.5").tag("claude-sonnet-5-5")
                        Text("Claude Haiku 5.5 (cheapest)").tag("claude-haiku-5-5")
                    }
                case .openAICompatible:
                    TextField("Address", text: $compatibleBaseURL, prompt: Text(ProviderConfiguration.defaultCompatibleBaseURL))
                    TextField("Model", text: $compatibleModel, prompt: Text("llama3.3, gpt-…, or a model your server offers"))
                    Text("Works with Ollama and LM Studio on this Mac, OpenAI, OpenRouter and similar. Plain http is only allowed to this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("API key") {
                if hasKey {
                    LabeledContent("Key") {
                        HStack {
                            Text("Saved in your Keychain")
                                .foregroundStyle(.secondary)
                            Button("Remove") { Task { await model.removeKey(for: kind) } }
                        }
                    }
                } else {
                    HStack {
                        SecureField(isLocal ? "Not needed for a server on this Mac" : "Paste your key", text: $keyEntry)
                        Button("Save") {
                            let entered = keyEntry
                            keyEntry = ""
                            Task { keyMessage = await model.saveKey(entered, for: kind) }
                        }
                        .disabled(keyEntry.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Text(keyMessage ?? "The key is stored only in the macOS Keychain and sent only to the service above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Limits") {
                Picker("Daily limit", selection: $dailyBudget) {
                    Text("50,000 tokens").tag(50_000)
                    Text("200,000 tokens").tag(200_000)
                    Text("1,000,000 tokens").tag(1_000_000)
                    Text("No limit").tag(0)
                }
                Toggle("Write a briefing each morning without being asked", isOn: $automaticBriefing)
                LabeledContent("Used today", value: usageText)
            }

            Section {
                HStack {
                    Button(isTesting ? "Testing…" : "Test Connection") {
                        isTesting = true
                        testResult = nil
                        Task {
                            testResult = await model.testAIConnection()
                            isTesting = false
                        }
                    }
                    .disabled(!enabled || isTesting)
                    if let testResult {
                        Text(testResult)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { await model.refreshAIStatus() }
    }

    private var disclosure: String {
        if isLocal && kind == .openAICompatible {
            return "Off by default. With a model on this Mac, nothing leaves your computer."
        }
        return "Off by default. When on, CraftPeep sends the headlines, excerpts and publisher names of the stories being summarised to the service you choose, under your own account with them. It never sends what you have read or saved, your interests, or your sources list. Nothing is sent unless you ask for a summary or a briefing, or switch on the automatic briefing below."
    }

    private var usageText: String {
        let usage = model.aiUsageToday
        guard usage.requests > 0 else { return "Nothing" }
        var text = "\(usage.requests) requests, \(usage.tokens.formatted()) tokens"
        if usage.unpricedRequests == usage.requests {
            text += ", cost unknown for this model"
        } else {
            let dollars = Double(usage.estimatedCostMicros) / 1_000_000
            text += ", about \(dollars.formatted(.currency(code: "USD").precision(.fractionLength(2...4))))"
            if usage.unpricedRequests > 0 { text += " plus \(usage.unpricedRequests) unpriced" }
        }
        return text
    }
}
