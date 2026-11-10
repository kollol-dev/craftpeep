import Foundation

enum Token: Equatable, Sendable {
    case number(Double)
    case string(String)
    case identifier(String)
    /// Operators and punctuation: + - * / % == != < <= > >= && || ! ? : . , ( ) [ ]
    case op(String)
    case end
}

struct PositionedToken: Equatable, Sendable {
    let token: Token
    /// Character offset in the source.
    let offset: Int
}

enum Lexer {
    static func tokenize(_ source: String) throws -> [PositionedToken] {
        let chars = Array(source)
        var tokens: [PositionedToken] = []
        var i = 0

        func isDigit(_ c: Character) -> Bool {
            c.isASCII && c.isNumber
        }

        let twoCharOperators: Set<String> = ["==", "!=", "<=", ">=", "&&", "||"]
        let singleCharOperators = "+-*/%<>!?:.,()[]"

        while i < chars.count {
            let c = chars[i]

            if c.isWhitespace {
                i += 1
                continue
            }

            let start = i

            // Numbers: 42, 3.14, .5
            if isDigit(c) || (c == "." && i + 1 < chars.count && isDigit(chars[i + 1])) {
                while i < chars.count, isDigit(chars[i]) { i += 1 }
                if i < chars.count, chars[i] == ".", i + 1 < chars.count, isDigit(chars[i + 1]) {
                    i += 1
                    while i < chars.count, isDigit(chars[i]) { i += 1 }
                }
                guard let value = Double(String(chars[start..<i])) else {
                    throw ExprError("Invalid number", offset: start)
                }
                tokens.append(PositionedToken(token: .number(value), offset: start))
                continue
            }

            // Identifiers: names and function names
            if c.isLetter || c == "_" || c == "$" {
                while i < chars.count,
                      chars[i].isLetter || chars[i].isNumber || chars[i] == "_" || chars[i] == "$" {
                    i += 1
                }
                tokens.append(PositionedToken(token: .identifier(String(chars[start..<i])), offset: start))
                continue
            }

            // Strings: 'single' or "double" quoted, with \n \t \r and \\ \' \" escapes
            if c == "'" || c == "\"" {
                let quote = c
                i += 1
                var value = ""
                var closed = false
                while i < chars.count {
                    let d = chars[i]
                    if d == "\\" {
                        guard i + 1 < chars.count else { break }
                        let escaped = chars[i + 1]
                        switch escaped {
                        case "n": value.append("\n")
                        case "t": value.append("\t")
                        case "r": value.append("\r")
                        default: value.append(escaped)
                        }
                        i += 2
                        continue
                    }
                    if d == quote {
                        closed = true
                        i += 1
                        break
                    }
                    value.append(d)
                    i += 1
                }
                guard closed else {
                    throw ExprError("Unterminated string", offset: start)
                }
                tokens.append(PositionedToken(token: .string(value), offset: start))
                continue
            }

            // Operators
            if i + 1 < chars.count {
                let two = String(chars[i...(i + 1)])
                if twoCharOperators.contains(two) {
                    tokens.append(PositionedToken(token: .op(two), offset: start))
                    i += 2
                    continue
                }
            }
            if singleCharOperators.contains(c) {
                tokens.append(PositionedToken(token: .op(String(c)), offset: start))
                i += 1
                continue
            }

            throw ExprError("Unexpected character '\(c)'", offset: i)
        }

        tokens.append(PositionedToken(token: .end, offset: chars.count))
        return tokens
    }
}
