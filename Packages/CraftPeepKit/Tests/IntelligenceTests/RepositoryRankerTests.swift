import Domain
import Foundation
import Testing
@testable import Intelligence

@Suite struct RepositoryRankerTests {
    private func history(_ id: Int64, stars: Int, createdDaysAgo: Double, baseline: Int? = nil, baselineHoursAgo: Double? = nil) -> RepositoryHistory {
        RepositoryHistory(
            repository: Repository(id: id, fullName: "o/r\(id)", url: "https://github.com/o/r\(id)", stars: stars, createdAt: now.addingTimeInterval(-createdDaysAgo * 86_400)),
            baselineStars: baseline,
            baselineAt: baselineHoursAgo.map { now.addingTimeInterval(-$0 * 3600) }
        )
    }

    @Test func prefersAMeasuredChangeOverAnEstimate() throws {
        let ranked = RepositoryRanker.rank([history(1, stars: 5000, createdDaysAgo: 400, baseline: 4400, baselineHoursAgo: 48)], now: now)
        let repository = try #require(ranked.first)
        #expect(repository.basis == .measured(gained: 600, overHours: 48))
        #expect(repository.starsPerDay == 300)
    }

    @Test func fallsBackToAgeForYoungRepositoriesOnly() {
        let young = RepositoryRanker.rank([history(1, stars: 3000, createdDaysAgo: 10)], now: now)
        #expect(young.first?.basis == .sinceCreation(days: 10))
        #expect(young.first?.starsPerDay == 300)

        // An old repository with no measurement yet has no honest momentum figure, so it is not listed.
        #expect(RepositoryRanker.rank([history(2, stars: 90_000, createdDaysAgo: 2000)], now: now).isEmpty)
        // A reading taken an hour ago is too recent to measure against.
        let tooSoon = RepositoryRanker.rank([history(3, stars: 3000, createdDaysAgo: 10, baseline: 2990, baselineHoursAgo: 1)], now: now)
        #expect(tooSoon.first?.basis == .sinceCreation(days: 10))
    }

    @Test func aRepositoryLosingStarsIsNotRising() {
        #expect(RepositoryRanker.rank([history(1, stars: 900, createdDaysAgo: 400, baseline: 1000, baselineHoursAgo: 48)], now: now).isEmpty)
        #expect(RepositoryRanker.rank([history(2, stars: 1000, createdDaysAgo: 5, baseline: 1000, baselineHoursAgo: 48)], now: now).isEmpty)
    }

    @Test func ordersByStarsPerDay() {
        let ranked = RepositoryRanker.rank([
            history(1, stars: 100_000, createdDaysAgo: 900, baseline: 99_900, baselineHoursAgo: 24),   // 100 a day
            history(2, stars: 2000, createdDaysAgo: 4),                                                  // 500 a day
            history(3, stars: 800, createdDaysAgo: 300, baseline: 200, baselineHoursAgo: 48)             // 300 a day
        ], now: now)
        #expect(ranked.map(\.id) == [2, 3, 1])
    }

    @Test func aBrandNewRepositoryIsNotDividedByAFractionOfADay() {
        let ranked = RepositoryRanker.rank([history(1, stars: 500, createdDaysAgo: 0.05)], now: now)
        #expect(ranked.first?.starsPerDay == 500)
    }
}
