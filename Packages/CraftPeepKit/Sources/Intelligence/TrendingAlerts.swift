import Domain
import Foundation

/// How much coverage a story needs before the daily alert mentions it.
public enum AlertStrictness: String, CaseIterable, Sendable, Identifiable {
    case strong
    case veryStrong

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .strong: "Strong: 3 or more publications"
        case .veryStrong: "Very strong: 5 or more publications"
        }
    }

    /// Independent publications reporting the story. Two feeds from one publisher count once.
    public var minimumPublications: Int {
        switch self {
        case .strong: 3
        case .veryStrong: 5
        }
    }

    /// Community points (Hacker News) that qualify a story on their own.
    public var minimumPoints: Int {
        switch self {
        case .strong: 300
        case .veryStrong: 600
        }
    }
}

/// Picks the few stories worth interrupting the user for. Rules only: no model is involved, so the alert
/// works with AI switched off and always gives the same answer for the same stories.
///
/// The caller passes stories already limited to the sources the user chose for alerts. Coverage is then
/// counted across every source, so a story from a chosen source that many publications picked up counts.
public struct TrendingAlertSelector: Sendable {
    public var strictness: AlertStrictness
    public var limit: Int
    /// Only stories first seen within this long before `now`.
    public var window: TimeInterval

    public init(strictness: AlertStrictness, limit: Int = 3, window: TimeInterval = 24 * 3600) {
        self.strictness = strictness
        self.limit = limit
        self.window = window
    }

    public func qualifies(_ story: ClusterSummary, now: Date) -> Bool {
        guard story.firstSeenAt >= now.addingTimeInterval(-window), story.firstSeenAt <= now else { return false }
        return story.independentSourceCount >= strictness.minimumPublications
            || (story.score ?? 0) >= strictness.minimumPoints
    }

    /// The qualifying stories not alerted before, most covered first.
    public func select(_ candidates: [ClusterSummary], alreadySent: Set<Int64>, now: Date) -> [ClusterSummary] {
        let picked = candidates
            .filter { !alreadySent.contains($0.id) && qualifies($0, now: now) }
            .sorted { a, b in
                if a.independentSourceCount != b.independentSourceCount {
                    return a.independentSourceCount > b.independentSourceCount
                }
                if (a.score ?? 0) != (b.score ?? 0) { return (a.score ?? 0) > (b.score ?? 0) }
                if a.firstSeenAt != b.firstSeenAt { return a.firstSeenAt > b.firstSeenAt }
                return a.id < b.id
            }
        return Array(picked.prefix(max(0, limit)))
    }
}

/// When the once-a-day alert is due. If the Mac was asleep or the app closed at the chosen time, the
/// alert is due as soon as it can run that day; it never runs twice for one day.
public struct DailyAlertSchedule: Sendable, Equatable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    /// Today's alert time in `calendar`'s time zone.
    public func fireDate(on day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    /// `lastRun` is when the alert last ran, whether or not anything qualified.
    public func isDue(now: Date, lastRun: Date?, calendar: Calendar) -> Bool {
        guard let fire = fireDate(on: now, calendar: calendar), now >= fire else { return false }
        if let lastRun, lastRun >= fire { return false }
        return true
    }
}

/// The notification text for the chosen stories. Headlines are shown as plain text.
public struct AlertMessage: Sendable, Equatable {
    public var title: String
    public var body: String
    /// The story a click opens: the first one.
    public var clusterID: Int64
    public var clusterIDs: [Int64]

    public init?(stories: [ClusterSummary]) {
        guard let first = stories.first else { return nil }
        title = stories.count == 1 ? "Trending story" : "\(stories.count) trending stories"
        body = stories.map { story in
            let headline = Self.clean(story.headline)
            return stories.count == 1 ? "\(headline) — \(Self.coverage(story))" : "• \(headline) — \(Self.coverage(story))"
        }.joined(separator: "\n")
        clusterID = first.id
        clusterIDs = stories.map(\.id)
    }

    static func coverage(_ story: ClusterSummary) -> String {
        let publications = story.independentSourceCount
        if publications >= 2 { return "\(publications) publications" }
        if let points = story.score, points > 0 { return "\(points) points" }
        return story.sourceNames.first ?? "1 publication"
    }

    /// Collapses whitespace and caps the length so one long headline cannot crowd out the others.
    static func clean(_ headline: String) -> String {
        let collapsed = headline.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > 120 ? String(collapsed.prefix(119)) + "…" : collapsed
    }
}
