import Foundation

/// The result type of every expression. Kept separate from the spec's JSONValue so this
/// module has no dependencies, and because expressions also need dates.
public enum ExprValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case date(Date)
    case array([ExprValue])
    case object([String: ExprValue])

    /// Truthiness used by `when`, `&&`, `||`, `!` and `?:`.
    /// null, false, 0, "" and empty arrays/objects are falsy; everything else is truthy.
    public var isTruthy: Bool {
        switch self {
        case .null: return false
        case .bool(let value): return value
        case .number(let value): return value != 0 && !value.isNaN
        case .string(let value): return !value.isEmpty
        case .date: return true
        case .array(let value): return !value.isEmpty
        case .object(let value): return !value.isEmpty
        }
    }

    /// How a value appears when it is pasted into text, e.g. "Hello {{ name }}".
    public var displayString: String {
        switch self {
        case .null: return ""
        case .bool(let value): return value ? "true" : "false"
        case .number(let value): return ExprValue.formatPlain(value)
        case .string(let value): return value
        case .date(let value): return ISO8601DateFormatter().string(from: value)
        case .array(let value): return value.map(\.displayString).joined(separator: ", ")
        case .object: return "[object]"
        }
    }

    static func formatPlain(_ value: Double) -> String {
        if value.isNaN || value.isInfinite { return "" }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return String(value)
    }
}

// MARK: - Literal conveniences (mainly for tests and for building scopes)

extension ExprValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension ExprValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
}

extension ExprValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .number(value) }
}

extension ExprValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension ExprValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: ExprValue...) { self = .array(elements) }
}

extension ExprValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, ExprValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

// MARK: - Errors

public struct ExprError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String
    /// Character offset in the expression source, when known.
    public let offset: Int?

    public init(_ message: String, offset: Int? = nil) {
        self.message = message
        self.offset = offset
    }

    public var description: String {
        if let offset {
            return "\(message) (at position \(offset))"
        }
        return message
    }
}
