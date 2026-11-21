import Domain
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            SourcesSettings(model: model)
                .tabItem { Label("Sources", systemImage: "dot.radiowaves.up.forward") }
            InterestsSettings(model: model)
                .tabItem { Label("Interests", systemImage: "heart.text.square") }
            AISettingsView(model: model)
                .tabItem { Label("AI", systemImage: "sparkles") }
            WidgetSettingsView(model: model)
                .tabItem { Label("Widgets", systemImage: "rectangle.on.rectangle") }
        }
        .frame(width: 700, height: 620)
    }
}

private struct GeneralSettings: View {
    @AppStorage("density") private var density = Density.balanced
    @AppStorage("showMenuBarItem") private var showMenuBarItem = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Picker("Story rows", selection: $density) {
                ForEach(Density.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Show CraftPeep in the menu bar", isOn: $showMenuBarItem)
            Toggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, wanted in
                    do {
                        if wanted { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        loginError = nil
                    } catch {
                        loginError = "macOS did not accept the change. \(error.localizedDescription)"
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Text("CraftPeep has no account and sends no usage data. It connects only to the sources you have switched on, without cookies. Stories older than 90 days are removed unless you saved them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct SourcesSettings: View {
    let model: AppModel
    @State private var newName = ""
    @State private var newURL = ""
    @State private var message: String?
    @State private var isAdding = false
    @State private var importing = false
    @State private var exporting = false

    var body: some View {
        VStack(spacing: 0) {
            List(model.sources) { source in
                HStack(alignment: .firstTextBaseline) {
                    Toggle(isOn: Binding(
                        get: { source.enabled },
                        set: { enabled in Task { await model.setEnabled(enabled, source: source) } }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.name)
                            Text(detail(source))
                                .font(.caption)
                                .foregroundStyle(source.failCount > 0 && source.enabled ? .primary : .secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    Text(source.tier.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if source.isUserAdded {
                        Button(role: .destructive) {
                            Task { await model.removeSource(source) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this feed and the stories fetched from it")
                        .accessibilityLabel("Remove \(source.name)")
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("Name (optional)", text: $newName)
                        .frame(width: 160)
                    TextField("https://example.com/feed.xml", text: $newURL)
                        .onSubmit(add)
                    Button("Add Feed", action: add)
                        .disabled(newURL.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
                }
                HStack {
                    Text(message ?? "Feeds you add are marked Unverified. RSS, Atom and JSON Feed over https.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Import OPML…") { importing = true }
                        .help("Add the feeds listed in a subscription file exported from another reader")
                    Button("Export OPML…") { exporting = true }
                        .help("Save your feeds as a subscription file other readers can import")
                }
            }
            .padding(12)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: OPMLFile.readableContentTypes) { result in
            guard case .success(let url) = result else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                message = "Could not read that file."
                return
            }
            Task { message = await model.importOPML(data) }
        }
        .fileExporter(
            isPresented: $exporting, document: OPMLFile(data: model.exportOPML()),
            contentType: OPMLFile.opml, defaultFilename: "CraftPeep Sources"
        ) { result in
            if case .failure = result { message = "Could not save the file." }
        }
    }

    private func add() {
        guard !isAdding else { return }
        isAdding = true
        Task {
            message = await model.addFeed(name: newName, url: newURL)
            if message == nil {
                newName = ""
                newURL = ""
                message = "Added."
            }
            isAdding = false
        }
    }

    private func detail(_ source: Source) -> String {
        if !source.enabled { return "Off" }
        if source.failCount > 0 {
            return "Failing: \(source.lastError ?? "unknown error")" + (source.lastOKAt.map { ". Last worked \($0.relative)" } ?? "")
        }
        if let lastOK = source.lastOKAt { return "Fetched \(lastOK.relative)" }
        return "Not fetched yet"
    }
}

private struct InterestsSettings: View {
    let model: AppModel
    @State private var keyword = ""
    @State private var level = Interest.Level.followed

    var body: some View {
        VStack(spacing: 0) {
            if model.interests.isEmpty {
                ContentUnavailableView(
                    "No interests yet",
                    systemImage: "heart.text.square",
                    description: Text("Follow a company, technology or word to rank matching stories higher. Mute one to hide them.")
                )
            } else {
                List(model.interests) { interest in
                    HStack {
                        Text(interest.keyword)
                        Spacer()
                        Picker("Level", selection: Binding(
                            get: { interest.level },
                            set: { newLevel in Task { await model.setInterest(interest.keyword, level: newLevel) } }
                        )) {
                            Text(Interest.Level.priority.label).tag(Interest.Level.priority)
                            Text(Interest.Level.followed.label).tag(Interest.Level.followed)
                            Text(Interest.Level.muted.label).tag(Interest.Level.muted)
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        Button {
                            Task { await model.removeInterest(interest) }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(interest.keyword)")
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("Swift, Anthropic, kubernetes…", text: $keyword)
                        .onSubmit(add)
                    Picker("Level", selection: $level) {
                        Text(Interest.Level.priority.label).tag(Interest.Level.priority)
                        Text(Interest.Level.followed.label).tag(Interest.Level.followed)
                        Text(Interest.Level.muted.label).tag(Interest.Level.muted)
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    Button("Add", action: add)
                        .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Matches whole words in headlines, and the companies and technologies CraftPeep tags.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }

    private func add() {
        let word = keyword.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return }
        keyword = ""
        Task { await model.setInterest(String(word.prefix(60)), level: level) }
    }
}
