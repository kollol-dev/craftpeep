import CryptoKit
import Domain
import Foundation

/// Cleans and validates raw items. Anything that fails validation is dropped, not repaired.
public enum Normaliser {
    public static let titleLimit = 300
    public static let excerptLimit = 500

    public static func normalise(_ items: [RawItem], source: Source, now: Date) -> [NewArticle] {
        var seen = Set<String>()
        return items.compactMap { item in
            guard let article = normalise(item, source: source, now: now),
                  seen.insert(article.canonicalURL).inserted
            else { return nil }
            return article
        }
    }

    public static func normalise(_ item: RawItem, source: Source, now: Date) -> NewArticle? {
        // Only web links are ever stored; relative links resolve against the source's site.
        guard let url = URLCanonicaliser.webURL(item.url, relativeTo: source.siteURL ?? source.url),
              let canonical = URLCanonicaliser.canonical(url.absoluteString)
        else { return nil }

        let title = HTMLText.truncate(HTMLText.plain(item.title), to: titleLimit)
        guard !title.isEmpty else { return nil }

        var excerpt = item.excerpt.map { HTMLText.truncate(HTMLText.plain($0), to: excerptLimit) }
        if excerpt?.isEmpty == true || excerpt == title { excerpt = nil }

        let author = item.author
            .map { HTMLText.truncate(HTMLText.plain($0), to: 120) }
            .flatMap { $0.isEmpty ? nil : $0 }

        let discussion = item.discussionURL
            .flatMap { URLCanonicaliser.webURL($0) }
            .map(\.absoluteString)

        return NewArticle(
            sourceID: source.id,
            externalID: item.externalID.map { String($0.prefix(500)) },
            url: url.absoluteString,
            canonicalURL: canonical,
            title: title,
            excerpt: excerpt,
            author: author,
            publishedAt: plausible(item.publishedAt, now: now),
            retrievedAt: now,
            contentHash: hash(title: title, excerpt: excerpt),
            score: item.score.flatMap { $0 >= 0 ? $0 : nil },
            commentCount: item.commentCount.flatMap { $0 >= 0 ? $0 : nil },
            discussionURL: discussion
        )
    }

    /// A date well in the future or before the web existed is a feed bug. Treat it as missing
    /// rather than guess.
    static func plausible(_ date: Date?, now: Date) -> Date? {
        guard let date else { return nil }
        let earliest = Date(timeIntervalSince1970: 788_918_400) // 1 January 1995
        guard date >= earliest, date <= now.addingTimeInterval(86_400) else { return nil }
        return date
    }

    static func hash(title: String, excerpt: String?) -> String {
        let digest = SHA256.hash(data: Data((title + "\n" + (excerpt ?? "")).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
