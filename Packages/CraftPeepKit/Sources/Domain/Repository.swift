import Foundation

/// A public code repository, as GitHub's search API describes it.
public struct Repository: Sendable, Equatable, Identifiable {
    /// GitHub's numeric id. Stable across renames.
    public var id: Int64
    public var fullName: String
    public var description: String?
    public var url: String
    public var language: String?
    public var topics: [String]
    public var stars: Int
    public var forks: Int
    public var createdAt: Date?
    public var pushedAt: Date?

    public init(
        id: Int64, fullName: String, description: String? = nil, url: String, language: String? = nil,
        topics: [String] = [], stars: Int, forks: Int = 0, createdAt: Date? = nil, pushedAt: Date? = nil
    ) {
        self.id = id
        self.fullName = fullName
        self.description = description
        self.url = url
        self.language = language
        self.topics = topics
        self.stars = stars
        self.forks = forks
        self.createdAt = createdAt
        self.pushedAt = pushedAt
    }
}

/// A repository together with the oldest star count CraftPeep itself recorded for it recently.
public struct RepositoryHistory: Sendable, Equatable {
    public var repository: Repository
    /// Stars when CraftPeep first saw the repository within the look-back window, and when that was.
    public var baselineStars: Int?
    public var baselineAt: Date?

    public init(repository: Repository, baselineStars: Int? = nil, baselineAt: Date? = nil) {
        self.repository = repository
        self.baselineStars = baselineStars
        self.baselineAt = baselineAt
    }
}

/// How fast a repository is gaining stars, and how that figure was arrived at.
public struct RisingRepository: Sendable, Equatable, Identifiable {
    public enum Basis: Sendable, Equatable {
        /// The difference between two star counts CraftPeep recorded itself.
        case measured(gained: Int, overHours: Double)
        /// Total stars divided by the repository's age. Used until two measurements exist.
        case sinceCreation(days: Double)
    }

    public var repository: Repository
    public var starsPerDay: Double
    public var basis: Basis

    public var id: Int64 { repository.id }

    public init(repository: Repository, starsPerDay: Double, basis: Basis) {
        self.repository = repository
        self.starsPerDay = starsPerDay
        self.basis = basis
    }
}

public protocol RepositoryStore: Sendable {
    /// Stores the repositories and records today's star count for each (once per day).
    func record(_ repositories: [Repository], at now: Date) async throws
    /// Repositories seen on or after `seenSince`, each with its oldest snapshot on or after `baselineSince`.
    func histories(seenSince: Date, baselineSince: Date) async throws -> [RepositoryHistory]
    /// Removes repositories not seen since `before` and snapshots older than `snapshotsBefore`.
    func purgeRepositories(notSeenSince before: Date, snapshotsBefore: Date) async throws
    func meta(_ key: String) async throws -> String?
    func setMeta(_ value: String?, for key: String) async throws
}
