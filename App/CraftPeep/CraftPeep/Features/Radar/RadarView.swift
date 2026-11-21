import Domain
import SwiftUI

extension RisingRepository {
    /// States the growth figure together with how it was obtained, so an estimate is never read as a measurement.
    var growthStatement: String {
        switch basis {
        case .measured(let gained, let overHours):
            let period = overHours < 36 ? "\(Int(overHours.rounded())) hours" : "\(Int((overHours / 24).rounded())) days"
            return "+\(gained.formatted()) stars in \(period), measured by CraftPeep"
        case .sinceCreation(let days):
            let age = days < 1.5 ? "a day" : "\(Int(days.rounded())) days"
            return "\(repository.stars.formatted()) stars in \(age) since it was created"
        }
    }
}

struct RadarListView: View {
    @Bindable var model: AppModel

    var body: some View {
        content
            .navigationTitle(SidebarSection.radar.title)
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button("All Languages") { model.repositoryLanguage = nil }
                            .disabled(model.repositoryLanguage == nil)
                        Divider()
                        ForEach(model.repositoryLanguages, id: \.self) { language in
                            Toggle(language, isOn: Binding(
                                get: { model.repositoryLanguage == language },
                                set: { model.repositoryLanguage = $0 ? language : nil }
                            ))
                        }
                    } label: {
                        Label("Filter by Language", systemImage: model.repositoryLanguage == nil
                              ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .help("Show only repositories written mainly in one language")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
    }

    @ViewBuilder
    private var content: some View {
        if model.repositories.isEmpty {
            if !model.searchText.isEmpty || model.repositoryLanguage != nil {
                ContentUnavailableView("No matching repositories", systemImage: "magnifyingglass")
            } else if let error = model.radarError {
                ContentUnavailableView("GitHub is not answering", systemImage: "exclamationmark.triangle", description: Text("\(error). CraftPeep will try again within the hour."))
            } else {
                ContentUnavailableView("Nothing yet", systemImage: "chevron.left.forwardslash.chevron.right", description: Text("CraftPeep asks GitHub for fast-growing repositories a few times a day."))
            }
        } else {
            List(model.repositories, selection: $model.selectedRepositoryID) { item in
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    Text(item.repository.fullName)
                        .font(.headline)
                        .lineLimit(1)
                    if let description = item.repository.description {
                        Text(description)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Text(([item.repository.language].compactMap { $0 } + [item.growthStatement]).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
                .tag(item.id)
                .accessibilityElement(children: .combine)
            }
            .listStyle(.inset)
        }
    }

    private var statusBar: some View {
        HStack {
            Text(statusText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var statusText: String {
        var parts = ["\(model.repositories.count) repositories"]
        parts.append(model.radarUpdated.map { "from GitHub \($0.relative)" } ?? "not fetched yet")
        if let error = model.radarError { parts.append(error) }
        return parts.joined(separator: " · ")
    }
}

struct RepositoryDetailView: View {
    let item: RisingRepository
    let model: AppModel
    @State private var message: String?
    @State private var isWorking = false

    private var repository: Repository { item.repository }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.block) {
                VStack(alignment: .leading, spacing: Spacing.row) {
                    HStack(spacing: Spacing.row) {
                        ForEach(([repository.language].compactMap { $0 } + repository.topics).prefix(8), id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .overlay(Capsule().strokeBorder(.quaternary))
                        }
                    }
                    Text(repository.fullName)
                        .font(.title2.weight(.semibold))
                        .textSelection(.enabled)
                    if let description = repository.description {
                        Text(description)
                            .textSelection(.enabled)
                    }
                }

                HStack(spacing: Spacing.row) {
                    Button("Open on GitHub") { AppModel.openWebLink(repository.url) }
                        .buttonStyle(.borderedProminent)
                    if model.isFollowingReleases(of: repository) {
                        Label("Following releases", systemImage: "checkmark")
                            .foregroundStyle(.secondary)
                    } else {
                        Button(isWorking ? "Following…" : "Follow Releases") {
                            isWorking = true
                            Task {
                                message = await model.followReleases(of: repository)
                                isWorking = false
                            }
                        }
                        .disabled(isWorking)
                        .help("New versions of this project will appear in your stories")
                    }
                }
                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.block, verticalSpacing: Spacing.row) {
                    GridRow {
                        Text("Growth").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.growthStatement)
                            Text(basisExplanation).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    GridRow {
                        Text("Stars").foregroundStyle(.secondary)
                        Text("\(repository.stars.formatted()) stars, \(repository.forks.formatted()) forks")
                    }
                    if let created = repository.createdAt {
                        GridRow {
                            Text("Created").foregroundStyle(.secondary)
                            Text(created.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    if let pushed = repository.pushedAt {
                        GridRow {
                            Text("Last push").foregroundStyle(.secondary)
                            Text(pushed.relative)
                        }
                    }
                    GridRow {
                        Text("Source").foregroundStyle(.secondary)
                        Text("GitHub search API" + (model.radarUpdated.map { ", fetched \($0.relative)" } ?? ""))
                    }
                }
            }
            .padding(Spacing.page)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("")
    }

    private var basisExplanation: String {
        switch item.basis {
        case .measured:
            "The difference between two star counts CraftPeep recorded itself."
        case .sinceCreation:
            "An estimate: total stars divided by age. It becomes a measurement once CraftPeep has seen the repository on two different days."
        }
    }
}
