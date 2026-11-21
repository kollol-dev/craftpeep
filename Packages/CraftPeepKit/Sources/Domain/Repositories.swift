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
    /// Files a source in a folder; nil or an empty name takes it out of any folder.
    func setFolder(_ folder: String?, sourceID: Int64) async throws
    /// Renames a folder for every source in it.
    func renameFolder(_ name: String, to newName: String) async throws
    /// Takes every source out of a folder. The sources themselves are kept.
    func removeFolder(_ name: String) async throws
    /// Chooses whether a source's stories can trigger the daily trending alert.
    func setAlertsEnabled(_ enabled: Bool, sourceID: Int64) async throws
    /// The same, for every source in a folder.
    func setAlertsEnabled(_ enabled: Bool, folder: String) async throws
    /// How authoritative the user judges the source to be. Affects ranking and verification, never fetching.
    func setTier(_ tier: SourceTier, sourceID: Int64) async throws
    /// Allows or forbids plain http for one source. Allowing it also clears the failure count, so the
    /// next refresh tries straight away.
    func setAllowsInsecureHTTP(_ allowed: Bool, sourceID: Int64) async throws
    /// For each source, when its newest stored story was published (or first seen, if it gave no date).
    /// Sources with nothing stored are absent.
    func newestStoryDates() async throws -> [Int64: Date]
    /// Adds a source the user typed in. Returns false if that URL is already present.
    func addUserSource(_ definition: SourceDefinition) async throws -> Bool
    /// Removes a source and every article fetched from it.
    func delete(sourceID: Int64) async throws
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

/// Which stories the daily trending alert has already mentioned, so none is repeated.
public protocol AlertRepository: Sendable {
    func sentClusterIDs(since date: Date) async throws -> Set<Int64>
    func recordSent(_ clusterIDs: [Int64], at date: Date) async throws
}
