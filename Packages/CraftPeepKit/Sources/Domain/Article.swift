import Foundation

/// One item exactly as an adapter read it from a source, before any cleaning.
/// Everything in here is untrusted.
public struct RawItem: Sendable, Equatable {
    public var externalID: String?
    public var url: String
    public var title: String
    /// May contain HTML.
    public var excerpt: String?
    public var author: String?
    public var publishedAt: Date?
    /// Community signal, where the source has one (Hacker News points).
    public var score: Int?
    public var commentCount: Int?
    /// Where the item is being discussed, if that differs from `url`.
    public var discussionURL: String?

    public init(
        externalID: String? = nil,
        url: String,
        title: String,
        excerpt: String? = nil,
        author: String? = nil,
        publishedAt: Date? = nil,
        score: Int? = nil,
        commentCount: Int? = nil,
        discussionURL: String? = nil
    ) {
        self.externalID = externalID
        self.url = url
        self.title = title
        self.excerpt = excerpt
        self.author = author
        self.publishedAt = publishedAt
        self.score = score
        self.commentCount = commentCount
        self.discussionURL = discussionURL
    }
}

/// A cleaned, validated article ready to store. Plain text only.
public struct NewArticle: Sendable, Equatable {
    public var sourceID: Int64
    public var externalID: String?
    public var url: String
    /// Key used to recognise the same page across sources and refreshes.
    public var canonicalURL: String
    public var title: String
    public var excerpt: String?
    public var author: String?
    /// Nil when the source gave no usable date. Never invented.
    public var publishedAt: Date?
    public var retrievedAt: Date
    /// Hash of title and excerpt, for change detection.
    public var contentHash: String
    public var score: Int?
    public var commentCount: Int?
    public var discussionURL: String?

    public init(
        sourceID: Int64,
        externalID: String?,
        url: String,
        canonicalURL: String,
        title: String,
        excerpt: String?,
        author: String?,
        publishedAt: Date?,
        retrievedAt: Date,
        contentHash: String,
        score: Int? = nil,
        commentCount: Int? = nil,
        discussionURL: String? = nil
    ) {
        self.sourceID = sourceID
        self.externalID = externalID
        self.url = url
        self.canonicalURL = canonicalURL
        self.title = title
        self.excerpt = excerpt
        self.author = author
        self.publishedAt = publishedAt
        self.retrievedAt = retrievedAt
        self.contentHash = contentHash
        self.score = score
        self.commentCount = commentCount
        self.discussionURL = discussionURL
    }
}

/// A stored article together with the source facts needed to show it.
public struct Story: Sendable, Equatable, Identifiable {
    public var id: Int64
    public var url: String
    public var canonicalURL: String
    public var title: String
    public var excerpt: String?
    public var author: String?
    public var publishedAt: Date?
    public var retrievedAt: Date
    public var score: Int?
    public var commentCount: Int?
    public var discussionURL: String?
    public var sourceID: Int64
    public var sourceName: String
    public var sourceTier: SourceTier

    public init(
        id: Int64,
        url: String,
        canonicalURL: String,
        title: String,
        excerpt: String?,
        author: String?,
        publishedAt: Date?,
        retrievedAt: Date,
        score: Int?,
        commentCount: Int?,
        discussionURL: String?,
        sourceID: Int64,
        sourceName: String,
        sourceTier: SourceTier
    ) {
        self.id = id
        self.url = url
        self.canonicalURL = canonicalURL
        self.title = title
        self.excerpt = excerpt
        self.author = author
        self.publishedAt = publishedAt
        self.retrievedAt = retrievedAt
        self.score = score
        self.commentCount = commentCount
        self.discussionURL = discussionURL
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.sourceTier = sourceTier
    }

    /// The time to sort and display by: publication time if the source gave one, else when we saw it.
    public var effectiveDate: Date { publishedAt ?? retrievedAt }
}
