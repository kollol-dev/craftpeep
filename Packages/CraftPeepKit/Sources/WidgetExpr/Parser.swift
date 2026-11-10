import Foundation

enum UnaryOp: Sendable, Equatable {
    case not, negate
}

enum BinaryOp: Sendable, Equatable {
    case or, and
    case eq, ne, lt, le, gt, ge
    case add, sub, mul, div, mod
}

indirect enum Node: Sendable, Equatable {
    case literal(ExprValue)
    case identifier(String)
    case unary(UnaryOp, Node)
    case binary(BinaryOp, Node, Node)
    case ternary(Node, Node, Node)
    case member(Node, String)
    case index(Node, Node)
    case call(String, [Node])
}

/// Recursive-descent parser with precedence climbing.
///
/// Precedence, loosest to tightest:
///   ?:   ||   &&   == !=   < <= > >=   + -   * / %   unary ! -   . [] ()
struct Parser {
    static let maxLength = 2000
    static let maxDepth = 64

    private static let precedence: [String: (level: Int, op: BinaryOp)] = [
        "||": (1, .or),
        "&&": (2, .and),
        "==": (3, .eq), "!=": (3, .ne),
        "<": (4, .lt), "<=": (4, .le), ">": (4, .gt), ">=": (4, .ge),
        "+": (5, .add), "-": (5, .sub),
        "*": (6, .mul), "/": (6, .div), "%": (6, .mod)
    ]

    private let tokens: [PositionedToken]
    private var position = 0
    private var depth = 0

    private init(tokens: [PositionedToken]) {
        self.tokens = tokens
    }

    static func parse(_ source: String) throws -> Node {
        guard source.count <= maxLength else {
            throw ExprError("Expression is too long (limit is \(maxLength) characters)")
        }
        var parser = Parser(tokens: try Lexer.tokenize(source))
        let node = try parser.parseTernary()
        guard case .end = parser.current.token else {
            throw ExprError(
                "Unexpected \(parser.describe(parser.current.token))",
                offset: parser.current.offset
            )
        }
        return node
    }

    // MARK: - Token helpers

    private var current: PositionedToken {
        tokens[position]
    }

    private mutating func advance() {
        if position < tokens.count - 1 {
            position += 1
        }
    }

    private func isOp(_ symbol: String) -> Bool {
        if case .op(let value) = current.token {
            return value == symbol
        }
        return false
    }

    private mutating func consumeOp(_ symbol: String) -> Bool {
        if isOp(symbol) {
            advance()
            return true
        }
        return false
    }

    private mutating func expectOp(_ symbol: String) throws {
        guard consumeOp(symbol) else {
            throw ExprError(
                "Expected '\(symbol)' but found \(describe(current.token))",
                offset: current.offset
            )
        }
    }

    private func describe(_ token: Token) -> String {
        switch token {
        case .number(let value): return "number \(ExprValue.formatPlain(value))"
        case .string: return "string"
        case .identifier(let name): return "'\(name)'"
        case .op(let symbol): return "'\(symbol)'"
        case .end: return "end of expression"
        }
    }

    private mutating func enter() throws {
        depth += 1
        if depth > Parser.maxDepth {
            throw ExprError("Expression is nested too deeply", offset: current.offset)
        }
    }

    // MARK: - Grammar

    private mutating func parseTernary() throws -> Node {
        try enter()
        defer { depth -= 1 }

        let condition = try parseBinary(minPrecedence: 1)
        if consumeOp("?") {
            let whenTrue = try parseTernary()
            try expectOp(":")
            let whenFalse = try parseTernary()
            return .ternary(condition, whenTrue, whenFalse)
        }
        return condition
    }

    private mutating func parseBinary(minPrecedence: Int) throws -> Node {
        var left = try parseUnary()
        while case .op(let symbol) = current.token,
              let entry = Parser.precedence[symbol],
              entry.level >= minPrecedence {
            advance()
            let right = try parseBinary(minPrecedence: entry.level + 1)
            left = .binary(entry.op, left, right)
        }
        return left
    }

    private mutating func parseUnary() throws -> Node {
        try enter()
        defer { depth -= 1 }

        if consumeOp("!") {
            let operand = try parseUnary()
            return .unary(.not, operand)
        }
        if consumeOp("-") {
            let operand = try parseUnary()
            return .unary(.negate, operand)
        }
        return try parsePostfix()
    }

    private mutating func parsePostfix() throws -> Node {
        var node = try parsePrimary()
        while true {
            if consumeOp(".") {
                guard case .identifier(let name) = current.token else {
                    throw ExprError("Expected a property name after '.'", offset: current.offset)
                }
                advance()
                node = .member(node, name)
            } else if consumeOp("[") {
                let index = try parseTernary()
                try expectOp("]")
                node = .index(node, index)
            } else {
                return node
            }
        }
    }

    private mutating func parsePrimary() throws -> Node {
        let token = current
        switch token.token {
        case .number(let value):
            advance()
            return .literal(.number(value))

        case .string(let value):
            advance()
            return .literal(.string(value))

        case .identifier(let name):
            advance()
            switch name {
            case "true": return .literal(.bool(true))
            case "false": return .literal(.bool(false))
            case "null": return .literal(.null)
            default: break
            }
            if consumeOp("(") {
                guard Functions.isKnown(name) else {
                    throw ExprError("Unknown function '\(name)'", offset: token.offset)
                }
                var arguments: [Node] = []
                if !isOp(")") {
                    repeat {
                        let argument = try parseTernary()
                        arguments.append(argument)
                    } while consumeOp(",")
                }
                try expectOp(")")
                return .call(name, arguments)
            }
            return .identifier(name)

        case .op("("):
            advance()
            let inner = try parseTernary()
            try expectOp(")")
            return inner

        case .op, .end:
            throw ExprError("Unexpected \(describe(token.token))", offset: token.offset)
        }
    }
}
