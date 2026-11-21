import Updater
import Domain
import Ingestion
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let model: AppModel
    /// Nil in snapshot mode, which has no updater.
    var updater: AppUpdater?

    var body: some View {
        TabView {
            GeneralSettings(updater: updater)
                .tabItem { Label("General", systemImage: "gearshape") }
            SourcesSettings(model: model)
                .tabItem { Label("Sources", systemImage: "dot.radiowaves.up.forward") }
            InterestsSettings(model: model)
                .tabItem { Label("Interests", systemImage: "heart.text.square") }
            AlertSettingsView(model: model)
                .tabItem { Label("Alerts", systemImage: "bell.badge") }
            AISettingsView(model: model)
                .tabItem { Label("AI", systemImage: "sparkles") }
            WidgetSettingsView(model: model)
                .tabItem { Label("Widgets", systemImage: "rectangle.on.rectangle") }
        }
        .frame(width: 700, height: 620)
    }
}

private struct GeneralSettings: View {
    let updater: AppUpdater?
    @AppStorage("density") private var density = Density.balanced
    @AppStorage("showMenuBarItem") private var showMenuBarItem = true
    @AppStorage(UnreadBadgeStyle.storageKey) private var badgeStyle = UnreadBadgeStyle.number
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Picker("Story rows", selection: $density) {
                ForEach(Density.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Show CraftPeep in the menu bar", isOn: $showMenuBarItem)
            Picker("Unread count", selection: $badgeStyle) {
                ForEach(UnreadBadgeStyle.allCases) { Text($0.title).tag($0) }
            }
            .help("How the menu bar and the Overview show unread top stories. A dot or nothing takes away the pressure to catch up.")
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
            if let updater, updater.isConfigured {
                Section("Updates") {
                    Toggle("Check for updates every day", isOn: Bindable(updater).automaticallyChecksForUpdates)
                    LabeledContent("Version \(updater.currentVersion)") {
                        Button("Check Now") { updater.checkForUpdates() }
                            .disabled(!updater.canCheckForUpdates)
                    }
                    Text("Updates come from CraftPeep's GitHub releases and are installed only if they carry the publisher's signature. The check sends no information about you or this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Keyboard, while the story list is selected") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    ForEach([
                        ("J / K", "Next or previous story"), ("Space or N", "Next unread story"),
                        ("M", "Mark read or unread"), ("S", "Read Later"), ("F", "Favourite"),
                        ("O or Return", "Open the original"), ("R", "Refresh"), ("Command-K", "Mark all as read"), ("Command-Return", "Open the original, from anywhere")
                    ], id: \.0) { key, action in
                        GridRow {
                            Text(key).font(.callout.monospaced())
                            Text(action).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Privacy") {
                Text("CraftPeep has no account and sends no usage data. It connects only to the sources you have switched on, without cookies, and to GitHub to check for updates. Stories older than 90 days are removed unless you saved them.")
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
    @State private var show = SourceListFilter.all
    @State private var newFolderFor: Source?
    @State private var newFolderName = ""

    /// The sources shown, grouped by folder, folders first in order, then those in none.
    private var groups: [(title: String, sources: [Source])] {
        let folders = Set(shown.compactMap(\.folder)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var result = folders.map { folder in (title: folder, sources: shown.filter { $0.folder == folder }) }
        let loose = shown.filter { $0.folder == nil }
        if !loose.isEmpty { result.append((title: "Not in a folder", sources: loose)) }
        return result
    }

    enum SourceListFilter: String, CaseIterable, Identifiable {
        case all, failing, quiet
        var id: String { rawValue }
    }

    private var failing: [Source] { model.sources.filter { $0.enabled && $0.failCount > 0 } }
    private var quiet: [Source] { model.sources.filter(model.isQuiet) }

    private var shown: [Source] {
        switch show {
        case .all: model.sources
        case .failing: failing
        case .quiet: quiet
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $show) {
                Text("All (\(model.sources.count))").tag(SourceListFilter.all)
                Text("Failing (\(failing.count))").tag(SourceListFilter.failing)
                Text("Quiet for 30 days (\(quiet.count))").tag(SourceListFilter.quiet)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)
            List { ForEach(groups, id: \.title) { group in Section(group.title) { ForEach(group.sources) { source in
                HStack(alignment: .firstTextBaseline) {
                    Toggle(isOn: Binding(
                        get: { source.enabled },
                        set: { enabled in Task { await model.setEnabled(enabled, source: source) } }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(source.name)
                                if source.allowsInsecureHTTP {
                                    Image(systemName: "lock.open")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .help("Plain http is allowed for this feed")
                                        .accessibilityLabel("Plain http allowed")
                                }
                            }
                            Text(detail(source))
                                .font(.caption)
                                .foregroundStyle(source.failCount > 0 && source.enabled ? .primary : .secondary)
                                .lineLimit(3)
                            if !source.allowsInsecureHTTP, needsInsecureHTTP(source) {
                                Button("Allow Plain http for This Feed") {
                                    Task { await model.setAllowsInsecureHTTP(true, source: source) }
                                }
                                .controlSize(.small)
                                .help("The site offers this feed only without encryption. Allowing it lets anyone on your network see or alter what this one feed sends.")
                            }
                        }
                    }
                    Spacer()
                    Menu {
                        Button("Not in a Folder") { Task { await model.setFolder(nil, source: source) } }
                        if !model.folders.isEmpty { Divider() }
                        ForEach(model.folders, id: \.self) { folder in
                            Button(folder) { Task { await model.setFolder(folder, source: source) } }
                        }
                        Divider()
                        Button("New Folder…") {
                            newFolderName = ""
                            newFolderFor = source
                        }
                    } label: {
                        Label(source.folder ?? "No folder", systemImage: "folder")
                            .lineLimit(1)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Move this source to a folder")
                    Picker("Trust", selection: Binding(
                        get: { source.tier },
                        set: { tier in Task { await model.setTier(tier, source: source) } }
                    )) {
                        ForEach(SourceTier.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                    .help("How authoritative this source is. Official sources rank higher and make a story count as official; Unverified ones rank lowest. It never stops a feed being fetched.")
                    if source.allowsInsecureHTTP {
                        Button {
                            Task { await model.setAllowsInsecureHTTP(false, source: source) }
                        } label: {
                            Image(systemName: "lock")
                        }
                        .buttonStyle(.borderless)
                        .help("Stop allowing plain http for this feed")
                        .accessibilityLabel("Require https for \(source.name)")
                    }
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
            } } } }  // source rows, group sections, groups, List
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
                    Text(message ?? "Feeds you add start as Unverified: that is a trust level, not an error. Change it from the menu beside each feed. RSS, Atom and JSON Feed.")
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
        .task { await model.loadSourceActivity() }
        .alert("New Folder", isPresented: Binding(get: { newFolderFor != nil }, set: { if !$0 { newFolderFor = nil } })) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                if let source = newFolderFor { Task { await model.setFolder(newFolderName, source: source) } }
                newFolderFor = nil
            }
            Button("Cancel", role: .cancel) { newFolderFor = nil }
        } message: {
            Text("The source moves into the new folder.")
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

    /// True when the last failure was the feed needing plain http. Includes the wording macOS used before
    /// CraftPeep checked redirects itself, so feeds that failed then still offer the way out.
    private func needsInsecureHTTP(_ source: Source) -> Bool {
        guard let error = source.lastError else { return false }
        return error.hasPrefix(IngestionError.insecureRedirectMessage)
            || error.hasPrefix("Only https is allowed")
            || error.contains("App Transport Security")
    }

    private func detail(_ source: Source) -> String {
        if !source.enabled { return "Off" }
        if source.failCount > 0 {
            return "Failing: \(source.lastError ?? "unknown error")" + (source.lastOKAt.map { ". Last worked \($0.relative)" } ?? "")
        }
        if let lastOK = source.lastOKAt {
            let newest = model.newestStory[source.id].map { "newest story \($0.relative)" } ?? "no stories in the last 90 days"
            return "Fetched \(lastOK.relative) · \(newest)"
        }
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
