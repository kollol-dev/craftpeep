import Domain
import Foundation

/// Parses RSS 2.0, RSS 1.0 (RDF) and Atom into raw items. Input is untrusted.
public enum FeedParser {
    public static let defaultItemLimit = 200

    public static func parse(_ data: Data, itemLimit: Int = defaultItemLimit) throws -> [RawItem] {
        let handler = Handler(itemLimit: itemLimit)
        let parser = XMLParser(data: data)
        // Explicit, although these are the defaults: never fetch or expand external entities.
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        parser.delegate = handler
        let completed = parser.parse()

        guard handler.sawFeedRoot else { throw IngestionError.notAFeed }
        // Real feeds are sometimes cut off or slightly broken. Keep what parsed cleanly;
        // only fail when nothing usable came out.
        if !completed, !handler.reachedLimit, handler.items.isEmpty {
            throw IngestionError.malformed(parser.parserError?.localizedDescription ?? "invalid XML")
        }
        return handler.items
    }

    private final class Handler: NSObject, XMLParserDelegate {
        private enum Field { case title, link, id, summary, content, date, updated, author }

        let itemLimit: Int
        private(set) var items: [RawItem] = []
        private(set) var sawFeedRoot = false
        private(set) var reachedLimit = false

        private var depth = 0
        private var itemDepth: Int?
        private var field: Field?
        private var fieldDepth = 0
        private var buffer = ""
        private var values: [Field: String] = [:]
        private var atomLink: String?
        private let dates = FeedDateParser()

        init(itemLimit: Int) {
            self.itemLimit = itemLimit
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String]
        ) {
            depth += 1
            let name = elementName.lowercased()

            if depth == 1 {
                sawFeedRoot = ["rss", "feed", "rdf:rdf"].contains(name)
                if !sawFeedRoot { parser.abortParsing() }
                return
            }

            if itemDepth == nil {
                if name == "item" || name == "entry" {
                    itemDepth = depth
                    values = [:]
                    atomLink = nil
                }
                return
            }

            guard let itemDepth, field == nil, depth == itemDepth + 1 else { return }

            switch name {
            case "title": begin(.title)
            case "guid", "id": begin(.id)
            case "description", "summary": begin(.summary)
            case "content", "content:encoded": begin(.content)
            case "pubdate", "published", "dc:date": begin(.date)
            case "updated": begin(.updated)
            case "author", "dc:creator": begin(.author)
            case "link":
                if let href = attributes["href"] {
                    // Atom: prefer the page itself over self, enclosure or reply links.
                    let relation = attributes["rel"] ?? "alternate"
                    if relation == "alternate" || atomLink == nil { atomLink = href }
                } else {
                    begin(.link)
                }
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if field != nil { buffer += string }
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if field != nil { buffer += String(decoding: CDATABlock, as: UTF8.self) }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?
        ) {
            defer { depth -= 1 }

            if let current = field, depth == fieldDepth {
                let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty, values[current] == nil { values[current] = text }
                field = nil
                buffer = ""
                return
            }

            if let start = itemDepth, depth == start {
                itemDepth = nil
                finishItem()
                if items.count >= itemLimit {
                    reachedLimit = true
                    parser.abortParsing()
                }
            }
        }

        private func begin(_ newField: Field) {
            field = newField
            fieldDepth = depth
            buffer = ""
        }

        private func finishItem() {
            let identifier = values[.id]
            // RSS allows a guid that is the permalink and no <link> at all.
            let link = values[.link] ?? atomLink ?? identifier.flatMap { $0.hasPrefix("http") ? $0 : nil }
            guard let link, let title = values[.title] else { return }

            items.append(RawItem(
                externalID: identifier,
                url: link,
                title: title,
                excerpt: values[.summary] ?? values[.content],
                author: values[.author],
                publishedAt: (values[.date] ?? values[.updated]).flatMap(dates.parse)
            ))
        }
    }
}

/// Feed dates come as RFC 822 (RSS) or ISO 8601 (Atom), with plenty of variation.
struct FeedDateParser {
    private let rfc822: [DateFormatter]
    private let iso = ISO8601DateFormatter()
    private let isoFractional: ISO8601DateFormatter

    init() {
        rfc822 = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEE, dd MMM yyyy HH:mm Z",
            "dd MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss zzz"
        ].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            return formatter
        }
        isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func parse(_ string: String) -> Date? {
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = iso.date(from: text) ?? isoFractional.date(from: text) { return date }
        for formatter in rfc822 {
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}
