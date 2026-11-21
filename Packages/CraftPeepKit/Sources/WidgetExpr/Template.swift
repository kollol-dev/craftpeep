import Foundation

/// A string that may contain `{{ expression }}` parts, such as
/// "https://example.com/q={{ encode(settings.query) }}&n={{ settings.count }}".
///
/// If the whole string is exactly one `{{ }}`, evaluation returns the raw value
/// (an array, number, bool...), which is what `each`, `when` and `color` need.
/// Otherwise the result is a string, with each expression shown via `displayString`.
public struct Template: Sendable, Equatable {
    enum Segment: Sendable, Equatable {
        case text(String)
        case expression(Expression)
    }

    let segments: [Segment]

    public static func parse(_ source: String) throws -> Template {
        let chars = Array(source)
        var segments: [Segment] = []
        var textBuffer = ""
        var i = 0

        while i < chars.count {
            let isOpening = chars[i] == "{" && i + 1 < chars.count && chars[i + 1] == "{"
            guard isOpening else {
                textBuffer.append(chars[i])
                i += 1
                continue
            }

            // Find the matching "}}", ignoring any "}}" inside a quoted string.
            var j = i + 2
            var quote: Character?
            var closing: Int?
            while j < chars.count {
                let c = chars[j]
                if let activeQuote = quote {
                    if c == "\\" {
                        j += 2
                        continue
                    }
                    if c == activeQuote {
                        quote = nil
                    }
                } else if c == "'" || c == "\"" {
                    quote = c
                } else if c == "}", j + 1 < chars.count, chars[j + 1] == "}" {
                    closing = j
                    break
                }
                j += 1
            }

            guard let end = closing else {
                throw ExprError("Unclosed '{{'", offset: i)
            }

            if !textBuffer.isEmpty {
                segments.append(.text(textBuffer))
                textBuffer = ""
            }
            let inner = String(chars[(i + 2)..<end])
            let expression = try Expression.parse(inner)
            segments.append(.expression(expression))
            i = end + 2
        }

        if !textBuffer.isEmpty {
            segments.append(.text(textBuffer))
        }
        return Template(segments: segments)
    }

    /// True when the template has no `{{ }}` parts.
    public var isConstant: Bool {
        !segments.contains { segment in
            if case .expression = segment { return true }
            return false
        }
    }

    public func evaluate(
        in scope: ExprScope,
        context: ExprContext = ExprContext()
    ) throws -> ExprValue {
        if segments.isEmpty {
            return .string("")
        }
        if segments.count == 1, case .expression(let expression) = segments[0] {
            return try expression.evaluate(in: scope, context: context)
        }
        var result = ""
        for segment in segments {
            switch segment {
            case .text(let text):
                result += text
            case .expression(let expression):
                let value = try expression.evaluate(in: scope, context: context)
                result += value.displayString
            }
        }
        return .string(result)
    }

    /// Evaluates and returns the display string.
    public func render(
        in scope: ExprScope,
        context: ExprContext = ExprContext()
    ) throws -> String {
        try evaluate(in: scope, context: context).displayString
    }
}
