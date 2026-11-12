import Domain
import SwiftUI
import WidgetBuilder
import WidgetSpec

/// Widgets on the desktop, and the gallery to add more from. Each widget's controls are generated
/// from the settings its definition declares, so a new widget needs no settings code.
struct WidgetSettingsView: View {
    let model: AppModel
    @State private var previewing: String?
    @State private var request = ""
    @State private var editing: String?

    var body: some View {
        Form {
            Section("Describe a widget") {
                if model.isAIEnabled {
                    HStack {
                        TextField(editing == nil ? "For example: the top AI stories, small" : "What should change?", text: $request)
                            .onSubmit(build)
                        Button(model.isBuildingWidget ? "Thinking…" : (editing == nil ? "Suggest" : "Suggest Change"), action: build)
                            .disabled(model.isBuildingWidget || request.trimmingCharacters(in: .whitespaces).isEmpty)
                        if editing != nil {
                            Button("Cancel") {
                                editing = nil
                                request = ""
                            }
                        }
                    }
                    if let editing, let item = model.widgets.first(where: { $0.id == editing }) {
                        Text("Changing your \(item.definition.name) widget.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let message = model.widgetBuilderMessage {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let suggestion = model.widgetSuggestion {
                        SuggestionView(suggestion: suggestion, model: model) {
                            editing = nil
                            request = ""
                        }
                    }
                    Text("Your words and the list of available widgets are sent to your AI provider. It can only choose among the widgets in the gallery and their settings; it cannot write a widget or run anything. Nothing is added until you say so.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Switch on AI in the AI tab to set up a widget by describing it. You can always add one from the gallery below without AI.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("On your desktop") {
                if model.widgets.isEmpty {
                    Text("No widgets yet. Add one from the gallery below.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.widgets) { item in
                    WidgetInstanceRow(item: item, model: model, onChangeWithWords: model.isAIEnabled ? {
                        editing = item.id
                        request = ""
                        model.discardWidgetSuggestion()
                    } : nil)
                }
            }

            Section("Gallery") {
                ForEach(model.gallery, id: \.id) { definition in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(definition.name)
                            if let description = definition.description {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Preview") { previewing = definition.id }
                            .popover(isPresented: Binding(
                                get: { previewing == definition.id },
                                set: { if !$0 { previewing = nil } }
                            )) {
                                DesktopWidgetContent(
                                    state: model.galleryPreviews[definition.id] ?? .loading, name: definition.name, perform: { _ in }
                                )
                                .frame(width: WidgetSize.medium.contentSize.width, height: WidgetSize.medium.contentSize.height)
                                .padding(12)
                            }
                        Button("Add to Desktop") { Task { await model.addWidget(definition) } }
                    }
                }
            }

            Section {
                Text("Widgets sit on the desktop, behind your windows, on every Space. Drag one to move it; right-click it for its size and to remove it. Widgets read what CraftPeep has already stored. They make no network requests of their own, use no AI, and cannot run anything.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await model.loadGalleryPreviews() }
    }

    private func build() {
        let words = request
        guard !words.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task { await model.suggestWidget(for: words, editing: editing) }
    }
}

/// A suggestion from the builder: what it chose, what it could not do, a live preview, and the decision.
private struct SuggestionView: View {
    let suggestion: WidgetSuggestion
    let model: AppModel
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(suggestion.definition.name), \(suggestion.proposal.size.label.lowercased())", systemImage: "sparkles")
                .font(.headline)
            Text(suggestion.proposal.explanation)
            if let unmet = suggestion.proposal.unmet {
                Label(unmet, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            }
            ForEach(suggestion.proposal.ignored, id: \.self) { note in
                Text("Left out: \(note).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            DesktopWidgetContent(state: suggestion.preview, name: suggestion.definition.name, perform: { _ in })
                .frame(width: suggestion.proposal.size.contentSize.width, height: min(suggestion.proposal.size.contentSize.height, 400))
                .accessibilityLabel("Preview of the suggested widget")
            HStack {
                Button(suggestion.replacing == nil ? "Add to Desktop" : "Apply Change") {
                    Task { await model.acceptWidgetSuggestion() }
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                Button("Discard") {
                    model.discardWidgetSuggestion()
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct WidgetInstanceRow: View {
    let item: DesktopWidgetItem
    let model: AppModel
    var onChangeWithWords: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.definition.name)
                    .font(.headline)
                Spacer()
                if let onChangeWithWords {
                    Button("Change with Words…", action: onChangeWithWords)
                }
                Button("Remove", role: .destructive) { Task { await model.removeWidget(item.id) } }
            }
            Picker("Size", selection: Binding(
                get: { item.size },
                set: { size in Task { await model.setWidgetSize(item.id, size) } }
            )) {
                ForEach(item.definition.sizes ?? [.small, .medium, .large], id: \.self) { Text($0.label).tag($0) }
            }
            ForEach(item.definition.settings ?? [], id: \.key) { setting in
                SettingControl(setting: setting, value: value(for: setting)) { newValue in
                    Task { await model.setWidgetSetting(item.id, key: setting.key, value: newValue) }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func value(for setting: WidgetSetting) -> WidgetSettingValue? {
        item.instance.settings[setting.key] ?? setting.defaultValue.flatMap(WidgetSettingValue.init)
    }
}

/// One control for one declared setting. Types this version does not draw are left out.
private struct SettingControl: View {
    let setting: WidgetSetting
    let value: WidgetSettingValue?
    let onChange: (WidgetSettingValue) -> Void
    @State private var text = ""

    var body: some View {
        switch setting.type {
        case .boolean:
            Toggle(setting.label, isOn: Binding(
                get: { value == .bool(true) },
                set: { onChange(.bool($0)) }
            ))
        case .select:
            Picker(setting.label, selection: Binding(
                get: { value ?? .string("") },
                set: { onChange($0) }
            )) {
                ForEach(setting.options ?? [], id: \.label) { option in
                    if let optionValue = WidgetSettingValue(option.value) {
                        Text(option.label).tag(optionValue)
                    }
                }
            }
        case .string:
            VStack(alignment: .leading, spacing: 2) {
                TextField(setting.label, text: $text)
                    .onSubmit { onChange(.string(String(text.trimmingCharacters(in: .whitespaces).prefix(80)))) }
                    .onAppear { if case .string(let current)? = value { text = current } }
                if let help = setting.help {
                    Text(help + " Press Return to apply.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .number:
            Stepper(value: Binding(
                get: { if case .number(let number)? = value { number } else { setting.min ?? 0 } },
                set: { onChange(.number($0)) }
            ), in: (setting.min ?? 0)...(setting.max ?? 100)) {
                Text(setting.label)
            }
        case .color, .stringList, .secret:
            EmptyView()
        }
    }
}

extension WidgetSettingValue: @retroactive Hashable {
    nonisolated public func hash(into hasher: inout Hasher) {
        switch self {
        case .bool(let value): hasher.combine(value)
        case .number(let value): hasher.combine(value)
        case .string(let value): hasher.combine(value)
        }
    }

    /// A setting's default or option value, when it is a plain value.
    nonisolated init?(_ json: JSONValue) {
        switch json {
        case .bool(let value): self = .bool(value)
        case .number(let value): self = .number(value)
        case .string(let value): self = .string(value)
        default: return nil
        }
    }
}
