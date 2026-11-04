import Foundation

// MARK: - Public API

/// Names available to an expression: `data`, `settings`, `secrets`, loop variables, and so on.
/// `now` is available automatically (from the context) unless the scope defines it.
public struct ExprScope: Sendable {
    public var variables: [String: ExprValue]

    public init(_ variables: [String: ExprValue] = [:]) {
        self.variables = variables
    }

    /// Returns a copy with one more name defined (used for `each`/`as` loop variables).
    public func adding(_ name: String, _ value: ExprValue) -> ExprScope {
        var copy = self
        copy.variables[name] = value
        return copy
    }
}

/// Settings that affect evaluation. Tests pass fixed values to stay deterministic.
public struct ExprContext: Sendable {
    public var now: Date
    public var locale: Locale
    public var timeZone: TimeZone
    /// Maximum number of AST nodes one evaluation may visit.
    public var stepLimit: Int

    public init(
        now: Date = Date(),
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        stepLimit: Int = 10_000
    ) {
        self.now = now
        self.locale = locale
        self.timeZone = timeZone
        self.stepLimit = stepLimit
    }
}

/// A parsed expression such as `q.changePct >= 0 ? 'positive' : 'negative'` (without the braces).
public struct Expression: Sendable, Equatable {
    public let source: String
    let root: Node

    public static func parse(_ source: String) throws -> Expression {
        let root = try Parser.parse(source)
        return Expression(source: source, root: root)
    }

    public func evaluate(
        in scope: ExprScope,
        context: ExprContext = ExprContext()
    ) throws -> ExprValue {
        var interpreter = Interpreter(scope: scope, context: context)
        return try interpreter.eval(root)
    }
}

// MARK: - Evaluator

struct Interpreter {
    let scope: ExprScope
    let context: ExprContext
    private var steps = 0

    init(scope: ExprScope, context: ExprContext) {
        self.scope = scope
        self.context = context
    }

    mutating func eval(_ node: Node) throws -> ExprValue {
        steps += 1
        if steps > context.stepLimit {
            throw ExprError("Expression is too complex (limit of \(context.stepLimit) steps exceeded)")
        }

        switch node {
        case .literal(let value):
            return value

        case .identifier(let name):
            if let value = scope.variables[name] {
                return value
            }
            if name == "now" {
                return .date(context.now)
            }
            throw ExprError("Unknown name '\(name)'")

        case .unary(let op, let operand):
            let value = try eval(operand)
            switch op {
            case .not:
                return .bool(!value.isTruthy)
            case .negate:
                switch value {
                case .null: return .null
                case .number(let number): return .number(-number)
                default: throw ExprError("Cannot negate a value that is not a number")
                }
            }

        case .binary(let op, let lhs, let rhs):
            if op == .and {
                let left = try eval(lhs)
                if !left.isTruthy { return left }
                return try eval(rhs)
            }
            if op == .or {
                let left = try eval(lhs)
                if left.isTruthy { return left }
                return try eval(rhs)
            }
            let left = try eval(lhs)
            let right = try eval(rhs)
            return try Operators.apply(op, left, right)

        case .ternary(let condition, let whenTrue, let whenFalse):
            let value = try eval(condition)
            if value.isTruthy {
                return try eval(whenTrue)
            }
            return try eval(whenFalse)

        case .member(let base, let name):
            let value = try eval(base)
            switch value {
            case .object(let object):
                return object[name] ?? .null
            case .array(let items):
                if name == "length" || name == "count" {
                    return .number(Double(items.count))
                }
                return .null
            case .string(let text):
                if name == "length" {
                    return .number(Double(text.count))
                }
                return .null
            default:
                return .null
            }

        case .index(let base, let indexNode):
            let value = try eval(base)
            let index = try eval(indexNode)
            switch (value, index) {
            case (.array(let items), .number(let number)):
                guard let position = Int(exactly: number), position >= 0, position < items.count else {
                    return .null
                }
                return items[position]
            case (.object(let object), .string(let key)):
                return object[key] ?? .null
            default:
                return .null
            }

        case .call(let name, let argumentNodes):
            var arguments: [ExprValue] = []
            for argumentNode in argumentNodes {
                let argument = try eval(argumentNode)
                arguments.append(argument)
            }
            return try Functions.call(name, arguments, context: context)
        }
    }
}

// MARK: - Operators

enum Operators {
    /// Missing data is common while a widget loads, so arithmetic with `null` yields `null`
    /// and ordering comparisons with `null` yield `false`, instead of throwing.
    static func apply(_ op: BinaryOp, _ left: ExprValue, _ right: ExprValue) throws -> ExprValue {
        switch op {
        case .eq:
            return .bool(left == right)
        case .ne:
            return .bool(left != right)
        case .lt, .le, .gt, .ge:
            return .bool(try compare(op, left, right))

        case .add:
            switch (left, right) {
            case (.null, _), (_, .null):
                return .null
            case (.number(let a), .number(let b)):
                return .number(a + b)
            case (.string, _), (_, .string):
                return .string(left.displayString + right.displayString)
            default:
                throw ExprError("Cannot add these values")
            }

        case .sub, .mul, .div, .mod:
            switch (left, right) {
            case (.null, _), (_, .null):
                return .null
            case (.number(let a), .number(let b)):
                switch op {
                case .sub:
                    return .number(a - b)
                case .mul:
                    return .number(a * b)
                case .div:
                    if b == 0 { throw ExprError("Division by zero") }
                    return .number(a / b)
                default:
                    if b == 0 { throw ExprError("Division by zero") }
                    return .number(a.truncatingRemainder(dividingBy: b))
                }
            default:
                throw ExprError("Arithmetic needs numbers")
            }

        case .and, .or:
            // Handled with short-circuiting in the interpreter; kept here for completeness.
            return .bool(left.isTruthy && right.isTruthy)
        }
    }

    private static func compare(_ op: BinaryOp, _ left: ExprValue, _ right: ExprValue) throws -> Bool {
        let order: Int
        switch (left, right) {
        case (.null, _), (_, .null):
            return false
        case (.number(let a), .number(let b)):
            order = a < b ? -1 : (a > b ? 1 : 0)
        case (.string(let a), .string(let b)):
            order = a < b ? -1 : (a > b ? 1 : 0)
        case (.date(let a), .date(let b)):
            order = a < b ? -1 : (a > b ? 1 : 0)
        default:
            throw ExprError("Cannot compare these values")
        }
        switch op {
        case .lt: return order < 0
        case .le: return order <= 0
        case .gt: return order > 0
        case .ge: return order >= 0
        default: return false
        }
    }
}
