import Foundation

/// What happened when one source was fetched. Written to the fetch log and to the source row.
public struct FetchOutcome: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        /// New content was received and parsed.
        case fetched
        /// The server said nothing changed (HTTP 304).
        case notModified
        case failed(message: String)
    }

    public var sourceID: Int64
    public var at: Date
    public var status: Status
    public var httpStatus: Int?
    public var itemsSeen: Int
    public var itemsNew: Int
    public var bytes: Int
    public var durationMillis: Int
    /// Validators to store for the next request. Nil leaves the stored ones untouched.
    public var validators: HTTPValidators?

    public init(
        sourceID: Int64,
        at: Date,
        status: Status,
        httpStatus: Int? = nil,
        itemsSeen: Int = 0,
        itemsNew: Int = 0,
        bytes: Int = 0,
        durationMillis: Int = 0,
        validators: HTTPValidators? = nil
    ) {
        self.sourceID = sourceID
        self.at = at
        self.status = status
        self.httpStatus = httpStatus
        self.itemsSeen = itemsSeen
        self.itemsNew = itemsNew
        self.bytes = bytes
        self.durationMillis = durationMillis
        self.validators = validators
    }

    public var isFailure: Bool {
        if case .failed = status { return true }
        return false
    }
}

public protocol SourceRepository: Sendable {
    /// Adds any definitions whose URL is not already stored. Existing rows are left alone,
    /// so user changes survive a catalogue update. Returns how many were added.
    @discardableResult
    func seed(_ definitions: [SourceDefinition]) async throws -> Int
    func allSources() async throws -> [Source]
    func enabledSources() async throws -> [Source]
    func setEnabled(_ enabled: Bool, sourceID: Int64) async throws
    /// Updates the source's health fields and appends to the fetch log.
    func record(_ outcome: FetchOutcome) async throws
}

public protocol ArticleRepository: Sendable {
    /// Inserts articles not seen before from their source and refreshes changed ones.
    /// Returns how many were new.
    func upsert(_ articles: [NewArticle]) async throws -> Int
    /// Newest first. `matching` is a full-text query over title and excerpt; nil or blank means all.
    func latestStories(limit: Int, matching query: String?) async throws -> [Story]
    func articleCount() async throws -> Int
}
