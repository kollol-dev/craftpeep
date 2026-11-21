import Domain
import Foundation

/// Parses JSON Feed 1.0 and 1.1 (jsonfeed.org). Read leniently, because publishers vary: ids may be
/// numbers, titles are optional, and 1.0 uses "author" where 1.1 uses "authors".
enum JSONFeedParser {
    static func parse(_ data: Data, itemLimit: Int) throws -> [RawItem] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IngestionError.malformed("invalid JSON")
        }
        guard let version = root["version"] as? String, version.hasPrefix("https://jsonfeed.org/version/") else {
            throw IngestionError.notAFeed
        }
        let dates = FeedDateParser()

        return (root["items"] as? [Any] ?? []).prefix(itemLimit).compactMap { element in
            guard let item = element as? [String: Any] else { return nil }

            let identifier: String? = switch item["id"] {
            case let text as String: text
            case let number as NSNumber: number.stringValue
            default: nil
            }
            let link = string(item["url"]) ?? string(item["external_url"])
                ?? identifier.flatMap { $0.hasPrefix("http") ? $0 : nil }
            let text = string(item["content_text"])
            let html = string(item["content_html"])
            let summary = string(item["summary"])

            // Short posts often have no title. Use the start of their text so they still have a headline.
            let title = string(item["title"])
                ?? (text ?? html.map(HTMLText.plain)).map { HTMLText.truncate(HTMLText.collapseWhitespace($0), to: 120) }
            guard let link, let title, !title.isEmpty else { return nil }

            let author = (item["authors"] as? [[String: Any]])?.first.flatMap { string($0["name"]) }
                ?? (item["author"] as? [String: Any]).flatMap { string($0["name"]) }

            return RawItem(
                externalID: identifier,
                url: link,
                title: title,
                excerpt: summary ?? text ?? html,
                author: author,
                publishedAt: (string(item["date_published"]) ?? string(item["date_modified"])).flatMap(dates.parse)
            )
        }
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
