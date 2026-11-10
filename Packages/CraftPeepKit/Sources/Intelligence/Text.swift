import Foundation

/// Turns a headline into a set of comparable tokens for clustering.
public enum TitleTokeniser {
    /// Words that say nothing about which story this is, stored in stemmed form.
    /// Announcement verbs are included on purpose: "X announces A" and "X announces B" are different stories.
    static let stopStems: Set<String> = [
        "a", "an", "the", "and", "or", "but", "of", "to", "in", "on", "at", "by", "for", "with", "from",
        "as", "is", "are", "was", "were", "be", "been", "it", "its", "this", "that", "these", "those",
        "has", "have", "had", "will", "can", "could", "may", "might", "would", "should", "do", "doe", "did",
        "not", "no", "now", "new", "how", "why", "what", "when", "who", "where", "which", "than", "then",
        "into", "over", "after", "before", "about", "up", "out", "off", "more", "most", "just", "also",
        "you", "your", "we", "our", "they", "their", "he", "she", "his", "her", "i", "my", "us", "all",
        "say", "said", "report", "via", "get", "make", "made", "use", "using", "here",
        "announc", "introduc", "launch", "releas", "unveil", "debut", "reveal",
        "show", "hn", "ask", "tell", "video", "podcast", "review", "week", "today"
    ]

    public static func tokens(_ title: String) -> Set<String> {
        var result = Set<String>()
        for word in words(title.lowercased()) {
            let isNumber = word.allSatisfy(\.isNumber)
            guard isNumber || word.count >= 2 else { continue }
            let stemmed = isNumber ? word : stem(word)
            guard !stopStems.contains(stemmed), !stopStems.contains(word) else { continue }
            result.insert(stemmed)
        }
        return result
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
    }

    /// A crude stemmer. It only has to map the forms of one word to the same string on both sides
    /// of a comparison; the result does not need to be a real word.
    static func stem(_ word: String) -> String {
        var stem = word
        if stem.count > 4, stem.hasSuffix("ies") {
            stem = String(stem.dropLast(3)) + "y"
        } else if stem.count > 5, stem.hasSuffix("ing") {
            stem = String(stem.dropLast(3))
        } else if stem.count > 4, stem.hasSuffix("ed") {
            stem = String(stem.dropLast(2))
        } else if stem.count > 3, stem.hasSuffix("s"), !stem.hasSuffix("ss"), !stem.hasSuffix("us"), !stem.hasSuffix("is") {
            stem = String(stem.dropLast(1))
        }
        if stem.count > 3, stem.hasSuffix("e") {
            stem = String(stem.dropLast(1))
        }
        // shipp -> ship, runn -> run
        if stem.count > 3, let last = stem.last, stem.dropLast().last == last, !"aeiouls".contains(last) {
            stem = String(stem.dropLast(1))
        }
        return stem
    }
}

/// Whole-word phrase matching: "meta" must not match "metadata".
struct PhraseText {
    /// Lower-cased words, space separated, with a space at each end.
    let folded: String
    /// The same with original capitalisation, for names that are only names when capitalised.
    let exact: String

    init(_ text: String) {
        let words = text.split(whereSeparator: { !($0.isLetter || $0.isNumber) })
        exact = " " + words.joined(separator: " ") + " "
        folded = exact.lowercased()
    }

    func contains(_ phrase: String) -> Bool {
        let needle = PhraseText(phrase).folded
        return needle.count > 2 && folded.contains(needle)
    }

    func containsExact(_ phrase: String) -> Bool {
        let needle = PhraseText(phrase).exact
        return needle.count > 2 && exact.contains(needle)
    }
}
