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
                    ToolbarItem(placement: .principal) {
                        Picker("Order", selection: $model.order) {
                            ForEach(StoryOrder.allCases) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        .pickerStyle(.segmented)
                        .help("Top ranks the last three days by importance. Latest is newest first.")
                    }
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
        .onChange(of: model.order) {
            Task { await model.reload() }
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
            List(model.stories) { item in
                StoryRow(item: item, model: model)
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
        var parts = ["\(model.stories.count) stories from \(model.sources.count) sources"]
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
    let item: StoryItem
    let model: AppModel
    @Environment(\.openURL) private var openURL
    @State private var showingCoverage = false

    private var story: ClusterSummary { item.summary }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                open(story.url)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(story.headline)
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
                    if !item.reasons.isEmpty {
                        Text(item.reasons.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the article in your browser")

            if story.memberCount > 1 {
                Button("\(story.sourceCount) sources") {
                    showingCoverage = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Show every source reporting this story")
                .popover(isPresented: $showingCoverage, arrowEdge: .trailing) {
                    CoverageView(item: item, model: model)
                }
            }
        }
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
    }

    private var metadata: String {
        var parts: [String] = []
        if let kind = story.kind {
            parts.append(kind.label)
        }
        let names = story.sourceNames
        parts.append(names.count > 2 ? "\(names[0]), \(names[1]) +\(names.count - 2)" : names.joined(separator: ", "))
        parts.append(story.verification.label)
        parts.append(story.lastSeenAt.formatted(.relative(presentation: .named)))
        if let score = story.score {
            parts.append("\(score) points")
        }
        if let comments = story.commentCount {
            parts.append("\(comments) comments")
        }
        return parts.joined(separator: " · ")
    }

    private func open(_ string: String) {
        openWebLink(string, with: openURL)
    }
}

/// Stored links are already limited to the web; check again at the point of use.
private func openWebLink(_ string: String, with openURL: OpenURLAction) {
    guard let url = URL(string: string), let scheme = url.scheme?.lowercased(),
          scheme == "https" || scheme == "http" else { return }
    openURL(url)
}

private struct CoverageView: View {
    let item: StoryItem
    let model: AppModel
    @State private var members: [Story] = []
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let kind = item.summary.kind {
                Text("\(kind.label) · \(basisText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(members) { member in
                Button {
                    openWebLink(member.url, with: openURL)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.title)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text("\(member.sourceName) · \(member.sourceTier.label) · \(member.effectiveDate.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 380, alignment: .leading)
        .task { members = await model.coverage(of: item) }
    }

    /// Says how the label was reached, so it can be questioned.
    private var basisText: String {
        let confidence = item.summary.kindConfidence.map { "\($0.rawValue) confidence" } ?? ""
        let basis = item.summary.kindBasis?.hasPrefix("rule:") == true ? "labelled by rule" : "labelled by model"
        return [basis, confidence].filter { !$0.isEmpty }.joined(separator: ", ")
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

extension StoryKind {
    var label: String {
        switch self {
        case .shipping: "Shipping"
        case .announcement: "Announcement"
        case .research: "Research"
        case .benchmark: "Benchmark"
        case .funding: "Funding / M&A"
        case .partnership: "Partnership"
        case .speculation: "Speculation"
        case .unverifiedClaim: "Unverified claim"
        }
    }
}

extension Verification {
    var label: String {
        switch self {
        case .official: "Official"
        case .corroborated: "Corroborated"
        case .singleSource: "Single source"
        case .unverified: "Community only"
        }
    }
}
