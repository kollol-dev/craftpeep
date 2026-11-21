import Domain
import Foundation

/// Knows how to ask one kind of source for its content and how to read the answer.
/// Fetching itself is done by the ingestion service, so limits and conditional requests
/// are applied in one place, and `parse` can be tested from fixtures with no network.
public protocol SourceAdapter: Sendable {
    /// Value for the Accept header.
    var accept: String { get }
    func parse(_ data: Data, source: Source) throws -> [RawItem]
}

public struct RSSAdapter: SourceAdapter {
    public init() {}

    public let accept = "application/atom+xml, application/rss+xml, application/feed+json, application/xml;q=0.9, text/xml;q=0.8, application/json;q=0.8, */*;q=0.1"

    public func parse(_ data: Data, source: Source) throws -> [RawItem] {
        try FeedParser.parse(data)
    }
}

/// Hacker News through the Algolia HN Search API: one request returns titles, links,
/// points and comment counts. The source's `url` is the search endpoint.
public struct HackerNewsAdapter: SourceAdapter {
    public init() {}

    public let accept = "application/json"

    public func parse(_ data: Data, source: Source) throws -> [RawItem] {
        let response: SearchResponse
        do {
            response = try JSONDecoder().decode(SearchResponse.self, from: data)
        } catch {
            throw IngestionError.malformed("unexpected Hacker News response")
        }

        return response.hits.compactMap { hit in
            guard let title = hit.title, !title.isEmpty else { return nil }
            let discussion = "https://news.ycombinator.com/item?id=\(hit.objectID)"
            // Ask HN, Show HN text posts and the like have no outside link: the discussion is the story.
            let link = (hit.url?.isEmpty == false ? hit.url : nil) ?? discussion
            return RawItem(
                externalID: hit.objectID,
                url: link,
                title: title,
                excerpt: hit.storyText,
                author: hit.author,
                publishedAt: hit.createdAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                score: hit.points,
                commentCount: hit.commentCount,
                discussionURL: discussion
            )
        }
    }

    private struct SearchResponse: Decodable {
        let hits: [Hit]
    }

    private struct Hit: Decodable {
        let objectID: String
        let title: String?
        let url: String?
        let author: String?
        let points: Int?
        let commentCount: Int?
        let createdAt: Int?
        let storyText: String?

        enum CodingKeys: String, CodingKey {
            case objectID, title, url, author, points
            case commentCount = "num_comments"
            case createdAt = "created_at_i"
            case storyText = "story_text"
        }
    }
}
