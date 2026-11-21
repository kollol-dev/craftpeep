import Foundation

/// Which adapter fetches a source.
public enum SourceKind: String, Sendable, Codable, CaseIterable {
    case rss
    case hackerNews = "hackernews"
}

/// How much weight a source's claims carry. Set by the bundled catalogue or by the user,
/// never by a model.
public enum SourceTier: String, Sendable, Codable, CaseIterable {
    /// The organisation the news is about, speaking for itself.
    case official
    /// Official technical documentation or release notes.
    case documentation
    /// Reputable independent reporting.
    case reporting
    /// Analyst or individual commentary.
    case analysis
    /// Community discussion and link aggregation.
    case community
    /// Not yet assessed. The default for anything the user adds.
    case unverified
}

/// Cache validators returned by a server, sent back on the next request.
public struct HTTPValidators: Sendable, Equatable {
    public var etag: String?
    public var lastModified: String?

    public init(etag: String? = nil, lastModified: String? = nil) {
        self.etag = etag
        self.lastModified = lastModified
    }

    public var isEmpty: Bool { etag == nil && lastModified == nil }
}

public struct Source: Sendable, Equatable, Identifiable {
    public var id: Int64
    public var kind: SourceKind
    public var name: String
    /// Feed URL, or the API endpoint for non-feed adapters.
    public var url: String
    public var siteURL: String?
    public var tier: SourceTier
    public var topics: [String]
    public var enabled: Bool
    public var refreshSeconds: Int
    public var validators: HTTPValidators
    public var lastFetchAt: Date?
    public var lastOKAt: Date?
    public var failCount: Int
    public var lastError: String?
    /// Added by the user rather than shipped in the catalogue.
    public var isUserAdded: Bool
    /// The user has allowed plain http for this feed, for sites that offer nothing else.
    public var allowsInsecureHTTP: Bool
    /// The folder the source is filed in, if any. One folder per source, as in most feed readers.
    public var folder: String?

    public init(
        id: Int64,
        kind: SourceKind,
        name: String,
        url: String,
        siteURL: String? = nil,
        tier: SourceTier,
        topics: [String] = [],
        enabled: Bool = true,
        refreshSeconds: Int = 1800,
        validators: HTTPValidators = HTTPValidators(),
        lastFetchAt: Date? = nil,
        lastOKAt: Date? = nil,
        failCount: Int = 0,
        lastError: String? = nil,
        isUserAdded: Bool = false,
        allowsInsecureHTTP: Bool = false,
        folder: String? = nil
    ) {
        self.folder = folder
        self.isUserAdded = isUserAdded
        self.allowsInsecureHTTP = allowsInsecureHTTP
        self.id = id
        self.kind = kind
        self.name = name
        self.url = url
        self.siteURL = siteURL
        self.tier = tier
        self.topics = topics
        self.enabled = enabled
        self.refreshSeconds = refreshSeconds
        self.validators = validators
        self.lastFetchAt = lastFetchAt
        self.lastOKAt = lastOKAt
        self.failCount = failCount
        self.lastError = lastError
    }
}

/// A source as described by the catalogue or typed in by the user, before it has a database id.
public struct SourceDefinition: Sendable, Equatable, Codable {
    public var kind: SourceKind
    public var name: String
    public var url: String
    public var siteURL: String?
    public var tier: SourceTier
    public var topics: [String]
    public var refreshSeconds: Int
    public var folder: String?

    public init(
        kind: SourceKind,
        name: String,
        url: String,
        siteURL: String? = nil,
        tier: SourceTier,
        topics: [String] = [],
        refreshSeconds: Int = 1800,
        folder: String? = nil
    ) {
        self.folder = folder
        self.kind = kind
        self.name = name
        self.url = url
        self.siteURL = siteURL
        self.tier = tier
        self.topics = topics
        self.refreshSeconds = refreshSeconds
    }
}
