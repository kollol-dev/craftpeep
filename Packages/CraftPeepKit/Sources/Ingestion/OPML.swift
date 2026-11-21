import Domain
import Foundation

/// One feed listed in an OPML file, as written there. Untrusted until turned into a source definition.
public struct OPMLFeed: Sendable, Equatable {
    public var title: String?
    public var xmlURL: String
    public var htmlURL: String?

    public init(title: String?, xmlURL: String, htmlURL: String?) {
        self.title = title
        self.xmlURL = xmlURL
        self.htmlURL = htmlURL
    }
}

public struct OPMLImportPlan: Sendable, Equatable {
    public var definitions: [SourceDefinition]
    /// Feeds listed with plain http, which CraftPeep will try over https.
    public var upgradedToHTTPS: Int
    /// Entries left out, each with the reason.
    public var skipped: [String]
}

/// Reading and writing OPML, the format feed readers use to move subscription lists between apps.
/// Folders are flattened: CraftPeep has none.
public enum OPML {
    public static let maximumBytes = 2 * 1024 * 1024
    public static let maximumFeeds = 2000

    public static func parse(_ data: Data) throws -> [OPMLFeed] {
        guard data.count <= maximumBytes else { throw IngestionError.tooLarge(limitBytes: maximumBytes) }
        let handler = Handler()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        parser.delegate = handler
        let completed = parser.parse()
        guard handler.sawRoot else { throw IngestionError.malformed("not an OPML file") }
        if !completed, handler.feeds.isEmpty, !handler.reachedLimit {
            throw IngestionError.malformed(parser.parserError?.localizedDescription ?? "invalid XML")
        }
        return handler.feeds
    }

    /// Turns listed feeds into sources the user is adding: https only, deduplicated, and marked
    /// Unverified, like any feed a user adds by hand.
    public static func plan(_ feeds: [OPMLFeed]) -> OPMLImportPlan {
        var plan = OPMLImportPlan(definitions: [], upgradedToHTTPS: 0, skipped: [])
        var seen = Set<String>()
        for feed in feeds {
            var address = feed.xmlURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if address.lowercased().hasPrefix("http://") {
                address = "https://" + address.dropFirst("http://".count)
                plan.upgradedToHTTPS += 1
            }
            guard let url = URL(string: address), url.scheme?.lowercased() == "https", let host = url.host(), !host.isEmpty else {
                plan.skipped.append("\(String(feed.xmlURL.prefix(80))): not a web address")
                continue
            }
            guard seen.insert(url.absoluteString).inserted else { continue }

            let name = feed.title.map { HTMLText.truncate(HTMLText.collapseWhitespace($0), to: 80) }.flatMap { $0.isEmpty ? nil : $0 } ?? host
            let site = feed.htmlURL.flatMap { URLCanonicaliser.webURL($0) }.map { "https://" + ($0.host() ?? host) + $0.path() }
            plan.definitions.append(SourceDefinition(
                kind: .rss, name: name, url: url.absoluteString, siteURL: site ?? "https://\(host)",
                tier: .unverified, topics: [], refreshSeconds: 3600
            ))
        }
        return plan
    }

    /// An OPML 2.0 document listing every feed source. Sources that are not feeds (Hacker News) are left out.
    public static func document(for sources: [Source], now: Date = Date()) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"

        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<opml version="2.0">"#,
            "  <head>",
            "    <title>CraftPeep sources</title>",
            "    <dateCreated>\(formatter.string(from: now))</dateCreated>",
            "  </head>",
            "  <body>"
        ]
        for source in sources where source.kind == .rss {
            var attributes = #"text="\#(escape(source.name))" title="\#(escape(source.name))" type="rss" xmlUrl="\#(escape(source.url))""#
            if let site = source.siteURL { attributes += #" htmlUrl="\#(escape(site))""# }
            lines.append("    <outline \(attributes)/>")
        }
        lines += ["  </body>", "</opml>", ""]
        return Data(lines.joined(separator: "\n").utf8)
    }

    static func escape(_ text: String) -> String {
        var output = ""
        for character in text {
            switch character {
            case "&": output += "&amp;"
            case "<": output += "&lt;"
            case ">": output += "&gt;"
            case "\"": output += "&quot;"
            case "'": output += "&apos;"
            default:
                // Control characters are not allowed in XML attributes; drop them.
                if character.unicodeScalars.allSatisfy({ $0.value >= 0x20 || $0 == "\t" }) { output.append(character) }
            }
        }
        return output
    }

    private final class Handler: NSObject, XMLParserDelegate {
        private(set) var feeds: [OPMLFeed] = []
        private(set) var sawRoot = false
        private(set) var reachedLimit = false
        private var depth = 0

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            depth += 1
            let name = elementName.lowercased()
            if depth == 1 {
                sawRoot = name == "opml"
                if !sawRoot { parser.abortParsing() }
                return
            }
            guard name == "outline" else { return }
            // Attribute names vary in case between apps.
            func attribute(_ key: String) -> String? {
                attributes.first { $0.key.lowercased() == key.lowercased() }?.value
            }
            guard let xmlURL = attribute("xmlUrl"), !xmlURL.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            // Some apps write an empty title and put the name in "text".
            let title = [attribute("title"), attribute("text")]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            feeds.append(OPMLFeed(title: title, xmlURL: xmlURL, htmlURL: attribute("htmlUrl")))
            if feeds.count >= OPML.maximumFeeds {
                reachedLimit = true
                parser.abortParsing()
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            depth -= 1
        }
    }
}
