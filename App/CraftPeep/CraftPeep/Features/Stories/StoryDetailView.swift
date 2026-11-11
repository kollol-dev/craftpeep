import Domain
import SwiftUI

struct StoryDetailView: View {
    let item: StoryItem
    let model: AppModel

    private var story: ClusterSummary { item.summary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.block) {
                header
                if let excerpt = story.excerpt {
                    Text(excerpt)
                        .font(.body)
                        .textSelection(.enabled)
                }
                actions
                aiSummary
                Divider()
                facts
                Divider()
                coverage
            }
            .padding(Spacing.page)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("")
    }

    /// AI text is always marked as such, with the model and time, and sits beside the sources it came from.
    @ViewBuilder
    private var aiSummary: some View {
        if let summary = model.summary {
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Label("AI summary", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(summary.text)
                    .textSelection(.enabled)
                Text("Why it matters: \(summary.whyItMatters)")
                    .textSelection(.enabled)
                Text("Written by \(summary.model) \(summary.createdAt.relative) from the sources below. It may be wrong; check the originals.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(Spacing.block)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        } else if model.isAIEnabled {
            HStack(spacing: Spacing.row) {
                Button {
                    Task { await model.summariseSelected() }
                } label: {
                    Label(model.isSummarising ? "Summarising…" : "Summarise with AI", systemImage: "sparkles")
                }
                .disabled(model.isSummarising)
                if let error = model.summaryError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.row) {
            HStack(spacing: Spacing.row) {
                if let kind = story.kind { KindBadge(kind: kind) }
                ForEach(story.entities, id: \.self) { entity in
                    Text(entity)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(.quaternary))
                }
            }
            Text(story.headline)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
        }
    }

    private var actions: some View {
        HStack(spacing: Spacing.row) {
            Button("Open Original") { AppModel.openWebLink(story.url) }
                .buttonStyle(.borderedProminent)
            if let discussion = story.discussionURL, discussion != story.url {
                Button("Open Discussion") { AppModel.openWebLink(discussion) }
            }
            Spacer()
            Button {
                Task { await model.toggleSaved(item.id) }
            } label: {
                Label(story.isSaved ? "Saved" : "Read Later", systemImage: story.isSaved ? "bookmark.fill" : "bookmark")
            }
            .help(story.isSaved ? "Remove from Read Later" : "Keep this story in Saved")
            Button {
                Task { await model.toggleFavourite(item.id) }
            } label: {
                Label("Favourite", systemImage: story.isFavourite ? "star.fill" : "star")
                    .labelStyle(.iconOnly)
            }
            .help(story.isFavourite ? "Remove Favourite" : "Mark as Favourite")
            .accessibilityLabel(story.isFavourite ? "Remove Favourite" : "Favourite")
        }
    }

    /// What CraftPeep worked out about the story, each with how it got there.
    private var facts: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.block, verticalSpacing: Spacing.row) {
            GridRow {
                Text("Support").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(story.verification.label)
                    Text(story.verification.explanation).font(.caption).foregroundStyle(.secondary)
                }
            }
            GridRow {
                Text("Kind").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(story.kind?.label ?? "Not classified")
                    Text(kindBasis).font(.caption).foregroundStyle(.secondary)
                }
            }
            GridRow {
                Text("Timeline").foregroundStyle(.secondary)
                Text(timeline)
            }
            if let score = story.score {
                GridRow {
                    Text("Community").foregroundStyle(.secondary)
                    Text("\(score) points" + (story.commentCount.map { ", \($0) comments" } ?? "") + " on Hacker News")
                }
            }
            if !item.reasons.isEmpty {
                GridRow {
                    Text("Ranked for").foregroundStyle(.secondary)
                    Text(item.reasons.joined(separator: " · "))
                }
            }
        }
    }

    private var kindBasis: String {
        guard story.kind != nil else { return "No rule matched this headline. CraftPeep does not guess." }
        let rule = story.kindBasis.map { $0.replacingOccurrences(of: "rule:", with: "") } ?? "unknown"
        let confidence = story.kindConfidence.map { ", \($0.rawValue) confidence" } ?? ""
        return "Labelled by the rule “\(rule)”\(confidence). Rules read the headline and link only."
    }

    private var timeline: String {
        let first = story.firstSeenAt.formatted(date: .abbreviated, time: .shortened)
        guard story.memberCount > 1, story.lastSeenAt.timeIntervalSince(story.firstSeenAt) > 60 else { return first }
        return "First report \(first), latest \(story.lastSeenAt.relative)"
    }

    private var coverage: some View {
        VStack(alignment: .leading, spacing: Spacing.row) {
            Text(story.memberCount == 1 ? "Source" : "\(story.memberCount) reports from \(story.sourceCount) sources")
                .font(.headline)
            ForEach(model.coverage) { member in
                Button {
                    AppModel.openWebLink(member.url)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.title)
                            .multilineTextAlignment(.leading)
                        Text(memberLine(member))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens this source in your browser")
            }
        }
    }

    private func memberLine(_ member: Story) -> String {
        var parts = [member.sourceName, member.sourceTier.label]
        if let published = member.publishedAt {
            parts.append("published \(published.formatted(date: .abbreviated, time: .shortened))")
        } else {
            // The source gave no date. Say what is known, not a guess.
            parts.append("no date given; first seen \(member.retrievedAt.relative)")
        }
        return parts.joined(separator: " · ")
    }
}
