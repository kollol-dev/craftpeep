import Domain
import Foundation
import WidgetExpr
import WidgetSpec

/// Where a widget's `query` sources get their stories. The app supplies this, backed by the same
/// ranking and filtering the main window uses, so a widget never sees anything the app would not show.
public protocol WidgetStorySource: Sendable {
    func stories(_ filter: StoryFilter, ranked: Bool, limit: Int) async throws -> [ClusterSummary]
}

/// Everything a widget needs to draw itself at one moment. Inert data: holding it does no work.
public struct WidgetSnapshot: Sendable, Equatable {
    /// `data`, `settings` and `now`, as the widget's expressions see them.
    public var variables: [String: ExprValue]
    public var asOf: Date
    /// Problems found while resolving, in words. A widget with issues still draws what it can.
    public var issues: [String]
    /// True when the widget asked the store for stories and none matched.
    public var hasNoStories: Bool

    public var scope: ExprScope { ExprScope(variables) }
}

/// The widgets shipped with the app. Each is an ordinary widget file; its settings are what a user adjusts.
public enum BundledWidgets {
    public static func newsList() throws -> WidgetDefinition {
        guard let url = Bundle.module.url(forResource: "news-list.widget", withExtension: "json") else {
            throw WidgetSpecError.malformed("the bundled News List widget is missing")
        }
        return try WidgetSpecLoader.load(from: url)
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

    public static func resolve(
        _ definition: WidgetDefinition,
        settings overrides: [String: ExprValue] = [:],
        source: any WidgetStorySource,
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
            case .query:
                queried = true
                do {
                    let filter = try filter(for: dataSource, scope: scope, context: context, subjects: subjects, now: now)
                    let limit = min(max(dataSource.limit ?? defaultQueryLimit, 1), 50)
                    let stories = try await source.stories(filter, ranked: dataSource.sort != "latest", limit: limit)
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
            hasNoStories: queried && !foundStories
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
    ) throws -> StoryFilter {
        func text(_ template: String) throws -> String {
            do {
                return try Template.parse(template).render(in: scope, context: context)
            } catch {
                throw QueryError(message: "could not evaluate '\(template)'")
            }
        }

        let conditions = dataSource.filter
        var filter = StoryFilter(since: now.addingTimeInterval(-(conditions?.sinceHours ?? 72) * 3600))

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
        filter.keptOnly = conditions?.saved == true
        return filter
    }

    /// What a widget's expressions can read about a story. Plain values only.
    static func value(_ story: ClusterSummary) -> ExprValue {
        .object([
            "id": .number(Double(story.id)),
            "headline": .string(story.headline),
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
