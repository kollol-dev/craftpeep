import Domain
import Foundation

/// Orders repositories by how fast they are gaining stars, and says how each figure was obtained.
public enum RepositoryRanker {
    /// A measurement needs readings at least this far apart to mean anything.
    public static let minimumMeasuredHours = 6.0
    /// "Stars since creation" is only a fair proxy for momentum while a repository is young.
    public static let maximumAgeDaysForCreationBasis = 45.0

    public static func rank(_ histories: [RepositoryHistory], now: Date) -> [RisingRepository] {
        histories.compactMap { rising($0, now: now) }
            .sorted { ($0.starsPerDay, $0.repository.stars, $0.id) > ($1.starsPerDay, $1.repository.stars, $1.id) }
    }

    static func rising(_ history: RepositoryHistory, now: Date) -> RisingRepository? {
        let repository = history.repository

        if let baseline = history.baselineStars, let at = history.baselineAt {
            let hours = now.timeIntervalSince(at) / 3600
            if hours >= minimumMeasuredHours {
                let gained = repository.stars - baseline
                // Stars can be removed. A loss is a real measurement, just not "rising".
                guard gained > 0 else { return nil }
                return RisingRepository(
                    repository: repository,
                    starsPerDay: Double(gained) / (hours / 24),
                    basis: .measured(gained: gained, overHours: hours)
                )
            }
        }

        guard let created = repository.createdAt else { return nil }
        let days = max(now.timeIntervalSince(created) / 86_400, 1)
        guard days <= maximumAgeDaysForCreationBasis, repository.stars > 0 else { return nil }
        return RisingRepository(repository: repository, starsPerDay: Double(repository.stars) / days, basis: .sinceCreation(days: days))
    }
}
