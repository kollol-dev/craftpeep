import Domain
import SwiftUI

struct MainView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { model.section }, set: { if let section = $0 { model.section = section } })) {
                ForEach(SidebarSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .badge(section == .overview ? model.unreadTopCount : 0)
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
        } content: {
            Group {
                if model.section == .radar {
                    RadarListView(model: model)
                } else {
                    StoryListView(model: model)
                }
            }
            .navigationSplitViewColumnWidth(min: 360, ideal: 460)
        } detail: {
            if model.section == .radar {
                if let repository = model.selectedRepository {
                    RepositoryDetailView(item: repository, model: model)
                } else {
                    ContentUnavailableView("No repository selected", systemImage: "chevron.left.forwardslash.chevron.right", description: Text("Choose a repository to see how fast it is growing and follow its releases."))
                }
            } else if model.showingBriefing, let briefing = model.briefing {
                BriefingView(briefing: briefing, model: model)
            } else if let item = model.selectedItem {
                StoryDetailView(item: item, model: model)
            } else {
                ContentUnavailableView("No story selected", systemImage: "doc.text", description: Text("Choose a story to see every source reporting it."))
            }
        }
        .searchable(text: $model.searchText, prompt: "Search \(model.section.title)")
        .task(id: model.searchText) {
            // Wait for a pause in typing before querying.
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await model.reload()
        }
    }
}

struct StoryListView: View {
    @Bindable var model: AppModel
    @AppStorage("density") private var density = Density.balanced
    @State private var showingFailures = false

    var body: some View {
        content
            .navigationTitle(model.section.title)
            .toolbar {
                if model.section == .news {
                    ToolbarItem {
                        Picker("Order", selection: $model.order) {
                            ForEach(StoryOrder.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .help("Top ranks the last three days by importance. Latest is newest first.")
                    }
                }
                ToolbarItem {
                    Menu {
                        Button("All Kinds") { model.kindFilter = [] }
                            .disabled(model.kindFilter.isEmpty)
                        Divider()
                        ForEach(StoryKind.allCases, id: \.self) { kind in
                            Toggle(isOn: Binding(
                                get: { model.kindFilter.contains(kind) },
                                set: { isOn in
                                    if isOn { model.kindFilter.insert(kind) } else { model.kindFilter.remove(kind) }
                                }
                            )) {
                                Label(kind.label, systemImage: kind.symbol)
                            }
                        }
                    } label: {
                        Label("Filter by Kind", systemImage: model.kindFilter.isEmpty
                              ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .help("Show only stories of the chosen kinds. Stories with no label are hidden while a filter is on.")
                }
                ToolbarItem {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        if model.isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(model.isRefreshing || model.startupError != nil)
                    .help("Fetch new stories from every source")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
    }

    @ViewBuilder
    private var content: some View {
        if let error = model.startupError {
            ContentUnavailableView("Cannot start", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if model.stories.isEmpty {
            emptyState
        } else {
            List(selection: $model.selection) {
                if model.section == .overview, model.searchText.isEmpty, let digest = model.digest {
                    DigestView(digest: digest)
                        .listRowSeparator(.hidden)
                        .selectionDisabled()
                    if model.briefing != nil || model.isAIEnabled {
                        BriefingRow(model: model)
                            .selectionDisabled()
                    }
                }
                ForEach(model.stories) { item in
                    StoryRow(item: item, density: density)
                        .tag(item.id)
                        .contextMenu { rowMenu(item) }
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.searchText.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        } else if !model.kindFilter.isEmpty {
            ContentUnavailableView {
                Label("Nothing of that kind", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("No stories here carry the kinds you chose.")
            } actions: {
                Button("Show All Kinds") { model.kindFilter = [] }
            }
        } else if model.section == .saved {
            ContentUnavailableView("Nothing saved", systemImage: "bookmark", description: Text("Stories you mark Read Later or Favourite are kept here, and are never removed by clean-up."))
        } else if model.isRefreshing {
            ProgressView("Fetching stories…")
        } else {
            ContentUnavailableView {
                Label("No stories yet", systemImage: "newspaper")
            } description: {
                Text("Refresh to fetch from \(model.sources.filter(\.enabled).count) sources.")
            } actions: {
                Button("Refresh") { Task { await model.refresh() } }
            }
        }
    }

    @ViewBuilder
    private func rowMenu(_ item: StoryItem) -> some View {
        Button("Open Original") { AppModel.openWebLink(item.summary.url) }
        if let discussion = item.summary.discussionURL, discussion != item.summary.url {
            Button("Open Discussion") { AppModel.openWebLink(discussion) }
        }
        Divider()
        Button(item.summary.isSaved ? "Remove from Read Later" : "Read Later") { Task { await model.toggleSaved(item.id) } }
        Button(item.summary.isFavourite ? "Remove Favourite" : "Favourite") { Task { await model.toggleFavourite(item.id) } }
        Divider()
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.summary.url, forType: .string)
        }
    }

    private var statusBar: some View {
        HStack(spacing: Spacing.row) {
            Text(statusText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if !model.failingSources.isEmpty {
                Button {
                    showingFailures = true
                } label: {
                    Label("\(model.failingSources.count) failing", systemImage: "exclamationmark.triangle")
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showingFailures, arrowEdge: .top) {
                    FailingSourcesView(sources: model.failingSources)
                }
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var statusText: String {
        if let error = model.loadError { return error }
        var parts = ["\(model.stories.count) stories"]
        if let updated = model.lastUpdated {
            parts.append("updated \(updated.relative)")
        } else {
            parts.append("never refreshed")
        }
        if let newCount = model.newInLastRefresh, newCount > 0 {
            parts.append("\(newCount) new")
        }
        return parts.joined(separator: " · ")
    }
}

/// A plain count of the last day. Says what it is; nothing here is written by a model.
private struct DigestView: View {
    let digest: DailyDigest

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.title3.weight(.semibold))
            Text(line)
                .foregroundStyle(.secondary)
            if !digest.mostMentioned.isEmpty {
                Text("Most mentioned: \(digest.mostMentioned.joined(separator: ", "))")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Spacing.row)
        .accessibilityElement(children: .combine)
    }

    private var line: String {
        var parts = ["\(digest.stories) stories in the last 24 hours"]
        if digest.official > 0 { parts.append("\(digest.official) from official sources") }
        if digest.multiSource > 0 { parts.append("\(digest.multiSource) covered by more than one publication") }
        return parts.joined(separator: " · ")
    }
}

/// The way into the AI briefing from Overview: open it if written, offer to write it if not.
private struct BriefingRow: View {
    let model: AppModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.row) {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if let briefing = model.briefing {
                Button {
                    model.selection = nil
                    model.showingBriefing = true
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.tight) {
                        Text("Today’s briefing")
                            .font(.headline)
                        Text(briefing.headline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the AI-written briefing")
            } else {
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    Button(model.isWritingBriefing ? "Writing briefing…" : "Write Today’s Briefing") {
                        Task { await model.writeBriefing() }
                    }
                    .disabled(model.isWritingBriefing)
                    Text(model.briefingError ?? "Sends the headlines and excerpts of the top stories to your AI provider.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, Spacing.tight)
    }
}

struct StoryRow: View {
    let item: StoryItem
    let density: Density

    private var story: ClusterSummary { item.summary }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.row) {
            // Unread marker: a shape, so it does not depend on colour or weight alone.
            Circle()
                .fill(story.isRead ? Color.clear : Color.accentColor)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(story.headline)
                    .font(.headline)
                    .fontWeight(story.isRead ? .regular : .semibold)
                    .foregroundStyle(story.isRead ? .secondary : .primary)
                    .lineLimit(density.headlineLines)
                if density.excerptLines > 0, let excerpt = story.excerpt {
                    Text(excerpt)
                        .foregroundStyle(.secondary)
                        .lineLimit(density.excerptLines)
                }
                HStack(spacing: 6) {
                    if let kind = story.kind {
                        Label(kind.label, systemImage: kind.symbol)
                            .labelStyle(.titleAndIcon)
                    }
                    Text(metadata)
                    if story.isSaved { Image(systemName: "bookmark.fill").accessibilityLabel("Saved for later") }
                    if story.isFavourite { Image(systemName: "star.fill").accessibilityLabel("Favourite") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                if density.showsReasons, !item.reasons.isEmpty {
                    Text(item.reasons.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, density.rowPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var sourcesText: String {
        let names = story.sourceNames
        return names.count > 2 ? "\(names[0]), \(names[1]) +\(names.count - 2)" : names.joined(separator: ", ")
    }

    private var metadata: String {
        var parts = [sourcesText, story.lastSeenAt.relative]
        if let score = story.score, score > 0 { parts.append("\(score) points") }
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        var parts = [story.isRead ? "" : "Unread", story.headline]
        if let kind = story.kind { parts.append(kind.label) }
        parts.append("from \(sourcesText)")
        parts.append(story.lastSeenAt.relative)
        parts.append(contentsOf: item.reasons)
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

struct FailingSourcesView: View {
    let sources: [Source]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sources that failed last time")
                .font(.headline)
            ForEach(sources) { source in
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                    Text(source.lastError ?? "Unknown error")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let lastOK = source.lastOKAt {
                        Text("Last worked \(lastOK.relative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(Spacing.block)
        .frame(width: 320, alignment: .leading)
    }
}
