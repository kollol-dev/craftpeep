import Domain
import SwiftUI

/// The menu bar companion: what is unread among the top stories, and a way into the app.
struct PulseView: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.unreadTopCount == 0 ? "All caught up" : "\(model.unreadTopCount) unread top stories")
                    .font(.headline)
                Spacer()
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh")
                    .accessibilityLabel("Refresh")
                }
            }
            .padding(.horizontal, Spacing.block)
            .padding(.vertical, 10)

            Divider()

            if model.pulse.isEmpty {
                Text(model.startupError ?? "Nothing new among the top stories.")
                    .foregroundStyle(.secondary)
                    .padding(Spacing.block)
            } else {
                ForEach(model.pulse) { item in
                    Button {
                        AppModel.openWebLink(item.summary.url)
                        Task { await model.markRead(item.id) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.summary.headline)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(([item.summary.sourceNames.first ?? ""] + item.reasons.prefix(1)).filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Spacing.block)
                    .padding(.vertical, 6)
                    .accessibilityHint("Opens the article and marks it read")
                }
            }

            Divider()

            HStack {
                Text(model.lastUpdated.map { "Updated \($0.relative)" } ?? "Never refreshed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open CraftPeep") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, Spacing.block)
            .padding(.vertical, 10)
        }
        .frame(width: 360)
    }
}
