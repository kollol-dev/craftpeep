import Domain
import SwiftUI

/// The AI-written briefing. Every item links back to the stored stories it was written from.
struct BriefingView: View {
    let briefing: Briefing
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.page) {
                VStack(alignment: .leading, spacing: Spacing.row) {
                    Label("AI briefing", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(briefing.headline)
                        .font(.title2.weight(.semibold))
                        .textSelection(.enabled)
                    Text("Written by \(briefing.model) \(briefing.createdAt.relative) from the stories linked under each item. CraftPeep chose the stories; the model wrote the explanation, and it may be wrong.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(briefing.items.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: Spacing.row) {
                        Text(item.title)
                            .font(.headline)
                        Text(item.whatHappened)
                        line("Why it matters", item.whyItMatters)
                        line("Who is affected", item.whoIsAffected)
                        line("Technical", item.technicalImplications)
                        line("Business", item.businessImplications)
                        line("Watch", item.whatToWatch)
                        HStack(spacing: Spacing.row) {
                            ForEach(item.clusterIDs, id: \.self) { id in
                                if let story = model.story(for: id) {
                                    Button(story.summary.sourceNames.first ?? "Story") {
                                        model.selection = id
                                    }
                                    .buttonStyle(.link)
                                    .help(story.summary.headline)
                                    .accessibilityLabel("Open the story: \(story.summary.headline)")
                                }
                            }
                        }
                        .font(.callout)
                    }
                    .textSelection(.enabled)
                }

                if !briefing.exploreNext.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.row) {
                        Text("Explore next")
                            .font(.headline)
                        ForEach(briefing.exploreNext, id: \.self) { suggestion in
                            Text("• \(suggestion)")
                        }
                    }
                    .textSelection(.enabled)
                }

                Button(model.isWritingBriefing ? "Writing…" : "Write Again") {
                    Task { await model.writeBriefing() }
                }
                .disabled(model.isWritingBriefing || !model.isAIEnabled)
            }
            .padding(Spacing.page)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("")
    }

    @ViewBuilder
    private func line(_ label: String, _ text: String?) -> some View {
        if let text, !text.isEmpty {
            (Text("\(label): ").foregroundStyle(.secondary) + Text(text))
        }
    }
}
