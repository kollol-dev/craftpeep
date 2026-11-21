import Domain
import Foundation
import WidgetExpr
import WidgetSpec

/// Where a widget's `query` sources get their stories. The app supplies this, backed by the same
/// ranking and filtering the main window uses, so a widget never sees anything the app would not show.
public protocol WidgetStorySource: Sendable {
    func stories(_ filter: StoryFilter, ranked: Bool, limit: Int) async throws -> [ClusterSummary]
}

/// Where a widget's repository queries get their data.
public protocol WidgetRepositorySource: Sendable {
    /// Fastest-growing first. `language` nil means any.
    func repositories(language: String?, limit: Int) async throws -> [RisingRepository]
}

/// Everything a widget needs to draw itself at one moment. Inert data: holding it does no work.
public struct WidgetSnapshot: Sendable, Equatable {
    /// `data`, `settings` and `now`, as the widget's expressions see them.
    public var variables: [String: ExprValue]
    public var asOf: Date
    /// Problems found while resolving, in words. A widget with issues still draws what it can.
    public var issues: [String]
    /// True when the widget asked the store for something and nothing matched.
    public var hasNoResults: Bool

    public var scope: ExprScope { ExprScope(variables) }
}

/// The widgets shipped with the app. Each is an ordinary widget file; its settings are what a user adjusts.
public enum BundledWidgets {
    static let files = ["news-list", "repository-list"]

    /// Every bundled widget, in the order the gallery shows them.
    public static func all() throws -> [WidgetDefinition] {
        try files.map(load)
    }

    public static func newsList() throws -> WidgetDefinition {
        try load("news-list")
    }

    public static func repositoryList() throws -> WidgetDefinition {
        try load("repository-list")
    }

    private static func load(_ name: String) throws -> WidgetDefinition {
        guard let url = Bundle.module.url(forResource: "\(name).widget", withExtension: "json") else {
            throw WidgetSpecError.malformed("the bundled widget '\(name)' is missing")
        }
        return try WidgetSpecLoader.load(from: url)
    }
}

/// The lists a story widget can show, for the host's view switcher.
public enum WidgetViews {
    public static let fixed: [(id: String, label: String)] = [
        ("overview", "Overview"), ("ai", "AI"), ("latest", "Latest"), ("saved", "Saved")
    ]

    public static func folder(_ name: String) -> String { "folder:" + name }

    public static func label(for id: String) -> String {
        if let fixed = fixed.first(where: { $0.id == id }) { return fixed.label }
        if id.hasPrefix("folder:") { return String(id.dropFirst(7)) }
        return "Overview"
    }
}

/// Resolves a widget's data sources. The only thing a widget can reach is the local store, through `source`.
public enum WidgetRuntime {
    public static let defaultQueryLimit = 10

    /// A widget's settings with the user's values laid over the file's defaults. Unknown keys are ignored
    /// and a value of the wrong type falls back to the default, so stored settings can never break a widget.
    public static func settings(for definition: WidgetDefinition, overrides: [String: ExprValue]) -> [String: ExprValue] {
        var values: [String: ExprValue] = [:]
        for setting in definition.settings ?? [] {
            // Secrets never enter the expression scope.
            guard setting.type != .secret else { continue }
            let fallback = setting.defaultValue.map(exprValue) ?? .null
            var value = overrides[setting.key] ?? fallback
            switch (setting.type, value) {
            case (.boolean, .bool), (.string, .string), (.color, .string): break
            case (.number, .number(let number)):
                value = .number(min(max(number, setting.min ?? -.infinity), setting.max ?? .infinity))
            case (.select, _):
                let allowed = (setting.options ?? []).map { exprValue($0.value) }
                if !allowed.contains(value) { value = fallback }
            case (.stringList, .array(let items)) where items.allSatisfy({ if case .string = $0 { true } else { false } }): break
            default: value = fallback
            }
            values[setting.key] = value
        }
        return values
    }

    /// Converts stored setting values into what expressions read.
    public static func values(_ settings: [String: WidgetSettingValue]) -> [String: ExprValue] {
        settings.mapValues { value in
            switch value {
            case .bool(let flag): .bool(flag)
            case .number(let number): .number(number)
            case .string(let text): .string(text)
            }
        }
    }

    public static func resolve(
        _ definition: WidgetDefinition,
        settings overrides: [String: ExprValue] = [:],
        source: any WidgetStorySource,
        repositories: (any WidgetRepositorySource)? = nil,
        subjects: [String: StoryFilter.Subject],
        now: Date = Date()
    ) async -> WidgetSnapshot {
        let settings = settings(for: definition, overrides: overrides)
        let scope = ExprScope(["settings": .object(settings), "now": .date(now)])
        let context = ExprContext(now: now)

        var data: [String: ExprValue] = [:]
        var issues: [String] = []
        var queried = false
        var foundStories = false

        for (name, dataSource) in (definition.data ?? [:]).sorted(by: { $0.key < $1.key }) {
            switch dataSource.type {
            case .static:
                data[name] = dataSource.value.map(exprValue) ?? .null
            case .time:
                data[name] = .object(["date": .date(now)])
            case .query where dataSource.from == "repositories":
                queried = true
                do {
                    guard let repositories else { throw QueryError(message: "repositories are not available here") }
                    let limit = min(max(dataSource.limit ?? defaultQueryLimit, 1), 50)
                    let language: String?
                    if let template = dataSource.filter?.language {
                        let text = try Template.parse(template).render(in: scope, context: context).trimmingCharacters(in: .whitespaces)
                        language = text.isEmpty ? nil : text
                    } else {
                        language = nil
                    }
                    let found = try await repositories.repositories(language: language, limit: limit)
                    foundStories = foundStories || !found.isEmpty
                    data[name] = .array(found.prefix(limit).map { value($0, now: now) })
                } catch {
                    data[name] = .array([])
                    issues.append("data.\(name): \((error as? QueryError)?.message ?? "could not read repositories")")
                }
            case .query:
                queried = true
                do {
                    let (filter, ranked) = try filter(for: dataSource, scope: scope, context: context, subjects: subjects, now: now)
                    let limit = min(max(dataSource.limit ?? defaultQueryLimit, 1), 50)
                    let stories = try await source.stories(filter, ranked: ranked, limit: limit)
                    foundStories = foundStories || !stories.isEmpty
                    data[name] = .array(stories.prefix(limit).map(value))
                } catch {
                    data[name] = .array([])
                    issues.append("data.\(name): \((error as? QueryError)?.message ?? "could not read stories")")
                }
            case .http, .rss, .system, .ai:
                // Declared in the spec, deliberately not available: widgets read the store, nothing else.
                data[name] = .null
                issues.append("data.\(name): '\(dataSource.type.rawValue)' sources are not available")
            }
        }

        return WidgetSnapshot(
            variables: ["data": .object(data), "settings": .object(settings), "now": .date(now)],
            asOf: now,
            issues: issues,
            hasNoResults: queried && !foundStories
        )
    }

    struct QueryError: Error {
        let message: String
    }

    static func filter(
        for dataSource: WidgetDataSource,
        scope: ExprScope,
        context: ExprContext,
        subjects: [String: StoryFilter.Subject],
        now: Date
    ) throws -> (StoryFilter, ranked: Bool) {
        func text(_ template: String) throws -> String {
            do {
                return try Template.parse(template).render(in: scope, context: context)
            } catch {
                throw QueryError(message: "could not evaluate '\(template)'")
            }
        }

        let conditions = dataSource.filter
        var filter = StoryFilter(since: now.addingTimeInterval(-(conditions?.sinceHours ?? 72) * 3600))
        var ranked = dataSource.sort != "latest"

        // A view names one of the app's own lists and sets the order with the filter.
        if let viewTemplate = conditions?.view {
            let view = try text(viewTemplate).trimmingCharacters(in: .whitespaces)
            switch view {
            case "overview", "":
                ranked = true
            case "ai":
                guard let known = subjects["ai"] else { throw QueryError(message: "unknown subject 'ai'") }
                filter.subject = known
                ranked = true
            case "latest":
                filter.since = now.addingTimeInterval(-14 * 86_400)
                ranked = false
            case "saved":
                filter.since = .distantPast
                filter.keptOnly = true
                ranked = false
            case let folder where folder.hasPrefix("folder:") && folder.count > 7:
                filter.folder = String(folder.dropFirst(7))
                filter.since = now.addingTimeInterval(-14 * 86_400)
                ranked = false
            default:
                throw QueryError(message: "unknown view '\(view)'")
            }
        }

        if let subjectTemplate = conditions?.subject {
            let subject = try text(subjectTemplate)
            if subject != "all", !subject.isEmpty {
                guard let known = subjects[subject] else { throw QueryError(message: "unknown subject '\(subject)'") }
                filter.subject = known
            }
        }
        if let entities = conditions?.entities, !entities.isEmpty {
            let names = try entities.prefix(20).map(text).filter { !$0.isEmpty }
            // An explicit list of tags takes the place of a subject.
            filter.subject = StoryFilter.Subject(entityNames: names)
        }
        if let kinds = conditions?.kinds, !kinds.isEmpty {
            filter.kinds = Set(kinds.compactMap(StoryKind.init(rawValue:)))
        }
        if conditions?.saved == true { filter.keptOnly = true }
        return (filter, ranked)
    }

    /// What a widget's expressions can read about a story. Plain values only.
    static func value(_ story: ClusterSummary) -> ExprValue {
        .object([
            "id": .number(Double(story.id)),
            "headline": .string(story.headline),
            "monogram": .string(monogram(story.sourceNames.first ?? "")),
            "sourceColor": .string(color(for: story.sourceNames.first ?? "")),
            "kindSymbol": story.kind.map { .string(kindSymbol($0)) } ?? .null,
            "excerpt": story.excerpt.map(ExprValue.string) ?? .null,
            "url": .string(story.url),
            "discussionURL": story.discussionURL.map(ExprValue.string) ?? .null,
            "source": .string(story.sourceNames.first ?? ""),
            "sources": .array(story.sourceNames.map(ExprValue.string)),
            "sourceCount": .number(Double(story.sourceCount)),
            "kind": story.kind.map { .string(kindLabel($0)) } ?? .null,
            "support": .string(story.verification.rawValue),
            "publishedAt": .date(story.lastSeenAt),
            "points": story.score.map { .number(Double($0)) } ?? .null,
            "comments": story.commentCount.map { .number(Double($0)) } ?? .null,
            "isRead": .bool(story.isRead),
            "isSaved": .bool(story.isSaved)
        ])
    }

    /// What a widget's expressions can read about a repository.
    static func value(_ item: RisingRepository, now: Date) -> ExprValue {
        let repository = item.repository
        let parts = repository.fullName.split(separator: "/", maxSplits: 1).map(String.init)
        return .object([
            "id": .number(Double(repository.id)),
            "fullName": .string(repository.fullName),
            "monogram": .string(monogram(parts.first ?? repository.fullName)),
            "sourceColor": .string(color(for: parts.first ?? repository.fullName)),
            "owner": .string(parts.first ?? ""),
            "name": .string(parts.last ?? repository.fullName),
            "description": repository.description.map(ExprValue.string) ?? .null,
            "url": .string(repository.url),
            "language": repository.language.map(ExprValue.string) ?? .null,
            "stars": .number(Double(repository.stars)),
            "starsPerDay": .number(item.starsPerDay.rounded()),
            "growth": .string(growthText(item)),
            "isMeasured": .bool({ if case .measured = item.basis { true } else { false } }())
        ])
    }

    /// A short growth statement that still says whether it is a measurement or an estimate.
    static func growthText(_ item: RisingRepository) -> String {
        func compact(_ number: Int) -> String {
            number >= 10_000 ? "\(number / 1000)k" : number >= 1000 ? String(format: "%.1fk", Double(number) / 1000) : "\(number)"
        }
        switch item.basis {
        case .measured(let gained, let overHours):
            let period = overHours < 36 ? "\(Int(overHours.rounded()))h" : "\(Int((overHours / 24).rounded()))d"
            return "+\(compact(gained)) stars in \(period)"
        case .sinceCreation(let days):
            return "\(compact(item.repository.stars)) stars in \(Int(max(days, 1).rounded()))d, est."
        }
    }

    /// The first letter of a name, for a small coloured badge.
    static func monogram(_ name: String) -> String {
        name.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "•"
    }

    /// A colour for a source, the same every time for the same name. All readable with white text.
    static let palette = ["#E5484D", "#F76B15", "#3E63DD", "#0090FF", "#12A594", "#30A46C", "#8E4EC6", "#D6409F", "#5B5BD6", "#978365"]

    static func color(for name: String) -> String {
        var hash: UInt64 = 5381
        for scalar in name.lowercased().unicodeScalars { hash = (hash &* 33) &+ UInt64(scalar.value) }
        return palette[Int(hash % UInt64(palette.count))]
    }

    static func kindSymbol(_ kind: StoryKind) -> String {
        switch kind {
        case .shipping: "shippingbox.fill"
        case .announcement: "megaphone.fill"
        case .research: "text.book.closed.fill"
        case .benchmark: "chart.bar.fill"
        case .funding: "banknote.fill"
        case .partnership: "person.2.fill"
        case .speculation: "questionmark.bubble.fill"
        case .unverifiedClaim: "exclamationmark.bubble.fill"
        }
    }

    static func kindLabel(_ kind: StoryKind) -> String {
        switch kind {
        case .shipping: "Shipping"
        case .announcement: "Announcement"
        case .research: "Research"
        case .benchmark: "Benchmark"
        case .funding: "Funding"
        case .partnership: "Partnership"
        case .speculation: "Speculation"
        case .unverifiedClaim: "Unverified"
        }
    }

    static func exprValue(_ json: JSONValue) -> ExprValue {
        switch json {
        case .null: .null
        case .bool(let value): .bool(value)
        case .number(let value): .number(value)
        case .string(let value): .string(value)
        case .array(let values): .array(values.map(exprValue))
        case .object(let values): .object(values.mapValues(exprValue))
        }
    }
}
