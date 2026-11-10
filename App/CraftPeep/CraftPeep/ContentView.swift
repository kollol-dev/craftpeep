import Domain
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var showingSources = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("CraftPeep")
                .searchable(text: $model.searchText, prompt: "Search stories")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
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
        .task { await model.start() }
        .task(id: model.searchText) {
            // Wait for a pause in typing before querying.
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await model.reload()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = model.startupError {
            ContentUnavailableView("Cannot start", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if model.stories.isEmpty {
            if !model.searchText.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            } else if model.isRefreshing {
                ProgressView("Fetching stories…")
            } else {
                ContentUnavailableView {
                    Label("No stories yet", systemImage: "newspaper")
                } description: {
                    Text("Refresh to fetch from \(model.sources.count) sources.")
                } actions: {
                    Button("Refresh") { Task { await model.refresh() } }
                }
            }
        } else {
            List(model.stories) { story in
                StoryRow(story: story)
            }
            .listStyle(.inset)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text(statusText)
                .foregroundStyle(.secondary)
            Spacer()
            if !model.failingSources.isEmpty {
                Button {
                    showingSources = true
                } label: {
                    Label("\(model.failingSources.count) failing", systemImage: "exclamationmark.triangle")
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showingSources, arrowEdge: .top) {
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
        var parts = ["\(model.storyCount) stories from \(model.sources.count) sources"]
        if let updated = model.lastUpdated {
            parts.append("updated \(updated.formatted(.relative(presentation: .named)))")
        } else {
            parts.append("never refreshed")
        }
        if let newCount = model.newInLastRefresh {
            parts.append("\(newCount) new in last refresh")
        }
        return parts.joined(separator: " · ")
    }
}

private struct StoryRow: View {
    let story: Story
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            open(story.url)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(story.title)
                    .font(.headline)
                    .lineLimit(2)
                if let excerpt = story.excerpt {
                    Text(excerpt)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .contextMenu {
            Button("Open Article") { open(story.url) }
            if let discussion = story.discussionURL, discussion != story.url {
                Button("Open Discussion") { open(discussion) }
            }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(story.url, forType: .string)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the article in your browser")
    }

    private var metadata: String {
        var parts = [story.sourceName, story.sourceTier.label]
        if let published = story.publishedAt {
            parts.append(published.formatted(.relative(presentation: .named)))
        } else {
            // The source gave no date. Say what we do know, not a guess.
            parts.append("first seen \(story.retrievedAt.formatted(.relative(presentation: .named)))")
        }
        if let score = story.score {
            parts.append("\(score) points")
        }
        if let comments = story.commentCount {
            parts.append("\(comments) comments")
        }
        return parts.joined(separator: " · ")
    }

    /// Stored links are already limited to the web; check again at the point of use.
    private func open(_ string: String) {
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return }
        openURL(url)
    }
}

private struct FailingSourcesView: View {
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
                        Text("Last worked \(lastOK.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
    }
}

extension SourceTier {
    var label: String {
        switch self {
        case .official: "Official"
        case .documentation: "Documentation"
        case .reporting: "Reporting"
        case .analysis: "Analysis"
        case .community: "Community"
        case .unverified: "Unverified"
        }
    }
}
