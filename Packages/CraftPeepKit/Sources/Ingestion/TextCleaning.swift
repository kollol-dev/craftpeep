import Foundation

/// Turns untrusted HTML fragments from feeds into plain text. Nothing from a feed is ever
/// rendered as HTML.
public enum HTMLText {
    /// Strips tags (and the contents of script and style), decodes entities and collapses whitespace.
    public static func plain(_ html: String) -> String {
        var output = ""
        output.reserveCapacity(html.count)

        var index = html.startIndex
        while index < html.endIndex {
            let character = html[index]
            guard character == "<" else {
                output.append(character)
                index = html.index(after: index)
                continue
            }

            // "a < b" is prose, not markup: a tag starts with a letter, "/", "!" or "?".
            let next = html.index(after: index)
            guard next < html.endIndex, html[next].isLetter || "/!?".contains(html[next]) else {
                output.append(character)
                index = next
                continue
            }

            guard let close = html[index...].firstIndex(of: ">") else {
                // An unclosed "<": treat the rest as text, not markup.
                output.append(contentsOf: html[index...])
                break
            }

            let tag = html[html.index(after: index)..<close].lowercased()
            index = html.index(after: close)
            output.append(" ")

            for blocked in ["script", "style"] where tag == blocked || tag.hasPrefix(blocked + " ") {
                if let end = html[index...].range(of: "</\(blocked)", options: .caseInsensitive) {
                    index = html[end.upperBound...].firstIndex(of: ">").map(html.index(after:)) ?? html.endIndex
                } else {
                    index = html.endIndex
                }
            }
        }

        return collapseWhitespace(decodeEntities(output))
    }

    /// Cuts at a word boundary and adds an ellipsis when text is longer than `limit` characters.
    public static func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let cut = text.prefix(limit)
        let trimmed = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return trimmed.trimmingCharacters(in: .whitespaces) + "…"
    }

    static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0 == "\u{00A0}" }).joined(separator: " ")
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "mdash": "—", "ndash": "–", "hellip": "…", "lsquo": "‘", "rsquo": "’",
        "ldquo": "“", "rdquo": "”", "copy": "©", "reg": "®", "trade": "™"
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var output = ""
        output.reserveCapacity(text.count)

        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            guard character == "&",
                  let semicolon = text[index...].prefix(12).firstIndex(of: ";") else {
                output.append(character)
                index = text.index(after: index)
                continue
            }

            let name = text[text.index(after: index)..<semicolon]
            if let decoded = decode(entity: name) {
                output.append(decoded)
                index = text.index(after: semicolon)
            } else {
                output.append(character)
                index = text.index(after: index)
            }
        }
        return output
    }

    private static func decode(entity name: Substring) -> String? {
        if let named = namedEntities[String(name)] { return named }
        guard name.hasPrefix("#") else { return nil }
        let digits = name.dropFirst()
        let value: UInt32? = if digits.hasPrefix("x") || digits.hasPrefix("X") {
            UInt32(digits.dropFirst(), radix: 16)
        } else {
            UInt32(digits, radix: 10)
        }
        guard let value, let scalar = Unicode.Scalar(value), value >= 0x20 || value == 0x09 || value == 0x0A else {
            return nil
        }
        return String(Character(scalar))
    }
}
