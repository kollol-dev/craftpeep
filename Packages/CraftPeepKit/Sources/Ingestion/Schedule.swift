import Domain
import Foundation

extension Source {
    /// Longest a failing source waits between attempts.
    public static let maximumBackoff: TimeInterval = 24 * 3600

    /// The source's interval, doubled for each consecutive failure up to a day.
    public var effectiveInterval: TimeInterval {
        let base = TimeInterval(max(refreshSeconds, 60))
        let multiplier = pow(2, Double(min(max(failCount, 0), 10)))
        return min(base * multiplier, max(base, Self.maximumBackoff))
    }

    public func isDue(at now: Date) -> Bool {
        guard let lastFetchAt else { return true }
        return now.timeIntervalSince(lastFetchAt) >= effectiveInterval
    }
}
