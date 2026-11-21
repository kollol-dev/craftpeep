import Foundation

/// The closed set of functions available inside `{{ }}`.
///
/// format round floor ceil clamp min max sum avg count join map filter first last
/// upper lower encode default ago
enum Functions {
    static let names: Set<String> = [
        "format", "round", "floor", "ceil", "clamp", "min", "max", "sum", "avg", "count",
        "join", "map", "filter", "first", "last", "upper", "lower", "encode", "default", "ago"
    ]

    static func isKnown(_ name: String) -> Bool {
        names.contains(name)
    }

    static func call(_ name: String, _ args: [ExprValue], context: ExprContext) throws -> ExprValue {
        switch name {
        case "format":
            try requireArgs(name, args, min: 2, max: 2)
            return try format(args[0], args[1], context: context)

        case "round":
            try requireArgs(name, args, min: 1, max: 2)
            guard let value = try numberArgument(args[0], name) else { return .null }
            var digits = 0
            if args.count == 2 {
                guard let requested = try numberArgument(args[1], name) else { return .null }
                digits = requested.isFinite ? Int(Swift.max(0, Swift.min(requested, 15))) : 0
            }
            let factor = pow(10.0, Double(digits))
            return .number((value * factor).rounded() / factor)

        case "floor":
            try requireArgs(name, args, min: 1, max: 1)
            guard let value = try numberArgument(args[0], name) else { return .null }
            return .number(value.rounded(.down))

        case "ceil":
            try requireArgs(name, args, min: 1, max: 1)
            guard let value = try numberArgument(args[0], name) else { return .null }
            return .number(value.rounded(.up))

        case "clamp":
            try requireArgs(name, args, min: 3, max: 3)
            guard let value = try numberArgument(args[0], name),
                  let low = try numberArgument(args[1], name),
                  let high = try numberArgument(args[2], name) else { return .null }
            return .number(Swift.min(Swift.max(value, low), high))

        case "min", "max":
            try requireArgs(name, args, min: 1, max: Int.max)
            let numbers = try numericList(args, name)
            let result = name == "min" ? numbers.min() : numbers.max()
            if let result { return .number(result) }
            return .null

        case "sum":
            try requireArgs(name, args, min: 1, max: 1)
            let numbers = try numericList(args, name)
            return .number(numbers.reduce(0, +))

        case "avg":
            try requireArgs(name, args, min: 1, max: 1)
            let numbers = try numericList(args, name)
            if numbers.isEmpty { return .null }
            return .number(numbers.reduce(0, +) / Double(numbers.count))

        case "count":
            try requireArgs(name, args, min: 1, max: 1)
            switch args[0] {
            case .null: return .number(0)
            case .array(let items): return .number(Double(items.count))
            case .string(let text): return .number(Double(text.count))
            case .object(let object): return .number(Double(object.count))
            default: throw ExprError("count() expects an array, string or object")
            }

        case "join":
            try requireArgs(name, args, min: 1, max: 2)
            let separator = args.count == 2 ? args[1].displayString : ", "
            switch args[0] {
            case .null: return .string("")
            case .array(let items):
                return .string(items.map(\.displayString).joined(separator: separator))
            default: throw ExprError("join() expects an array")
            }

        case "map":
            try requireArgs(name, args, min: 2, max: 2)
            guard case .string(let field) = args[1] else {
                throw ExprError("map() needs a field name as its second argument")
            }
            switch args[0] {
            case .null: return .array([])
            case .array(let items):
                let mapped = items.map { (item: ExprValue) -> ExprValue in
                    if case .object(let object) = item {
                        return object[field] ?? .null
                    }
                    return .null
                }
                return .array(mapped)
            default: throw ExprError("map() expects an array")
            }

        case "filter":
            try requireArgs(name, args, min: 2, max: 3)
            guard case .string(let field) = args[1] else {
                throw ExprError("filter() needs a field name as its second argument")
            }
            switch args[0] {
            case .null: return .array([])
            case .array(let items):
                let kept = items.filter { (item: ExprValue) -> Bool in
                    guard case .object(let object) = item else { return false }
                    let fieldValue = object[field] ?? .null
                    if args.count == 3 {
                        return fieldValue == args[2]
                    }
                    return fieldValue.isTruthy
                }
                return .array(kept)
            default: throw ExprError("filter() expects an array")
            }

        case "first", "last":
            try requireArgs(name, args, min: 1, max: 1)
            switch args[0] {
            case .null: return .null
            case .array(let items):
                let element = name == "first" ? items.first : items.last
                return element ?? .null
            default: throw ExprError("\(name)() expects an array")
            }

        case "upper", "lower":
            try requireArgs(name, args, min: 1, max: 1)
            if case .null = args[0] { return .null }
            let text = args[0].displayString
            return .string(name == "upper" ? text.uppercased() : text.lowercased())

        case "encode":
            try requireArgs(name, args, min: 1, max: 1)
            if case .null = args[0] { return .string("") }
            let allowed = CharacterSet(
                charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
            )
            let encoded = args[0].displayString.addingPercentEncoding(withAllowedCharacters: allowed)
            return .string(encoded ?? "")

        case "default":
            try requireArgs(name, args, min: 2, max: 2)
            switch args[0] {
            case .null: return args[1]
            case .string(let text) where text.isEmpty: return args[1]
            default: return args[0]
            }

        case "ago":
            try requireArgs(name, args, min: 1, max: 1)
            switch args[0] {
            case .null: return .null
            case .date(let date): return .string(ago(date, now: context.now))
            default: throw ExprError("ago() expects a date")
            }

        default:
            throw ExprError("Unknown function '\(name)'")
        }
    }

    // MARK: - Argument helpers

    private static func requireArgs(_ name: String, _ args: [ExprValue], min: Int, max: Int) throws {
        guard args.count >= min, args.count <= max else {
            let expected: String
            if max == Int.max {
                expected = "at least \(min)"
            } else if min == max {
                expected = "\(min)"
            } else {
                expected = "\(min) to \(max)"
            }
            throw ExprError("\(name)() takes \(expected) argument(s) but got \(args.count)")
        }
    }

    /// Returns nil for null, the number for numbers, and throws for anything else.
    private static func numberArgument(_ value: ExprValue, _ function: String) throws -> Double? {
        switch value {
        case .null: return nil
        case .number(let number): return number
        default: throw ExprError("\(function)() expects a number")
        }
    }

    /// Numbers from the arguments; a single array argument is flattened. Nulls are skipped.
    private static func numericList(_ args: [ExprValue], _ function: String) throws -> [Double] {
        var source = args
        if args.count == 1, case .array(let items) = args[0] {
            source = items
        }
        var result: [Double] = []
        for value in source {
            if let number = try numberArgument(value, function) {
                result.append(number)
            }
        }
        return result
    }

    // MARK: - format

    private static func format(
        _ value: ExprValue,
        _ pattern: ExprValue,
        context: ExprContext
    ) throws -> ExprValue {
        guard case .string(let pattern) = pattern else {
            throw ExprError("format() needs a pattern string as its second argument")
        }
        switch value {
        case .null:
            return .string("")
        case .number(let number):
            return .string(formatNumber(number, pattern: pattern) ?? value.displayString)
        case .date(let date):
            let formatter = DateFormatter()
            formatter.locale = context.locale
            formatter.timeZone = context.timeZone
            formatter.dateFormat = pattern
            return .string(formatter.string(from: date))
        default:
            return .string(value.displayString)
        }
    }

    private struct NumberSection {
        var prefix: String
        var suffix: String
        var decimals: Int
        var grouping: Bool
    }

    /// Understands patterns like "0", "0.00", "#,##0.0", "+0.00;-0.00", "0.0 pts".
    /// A second section after ";" is used for negative numbers.
    private static func parseSection(_ section: String) -> NumberSection? {
        let chars = Array(section)
        guard let first = chars.firstIndex(where: { $0 == "0" || $0 == "#" }),
              let last = chars.lastIndex(where: { $0 == "0" || $0 == "#" }) else {
            return nil
        }
        let prefix = String(chars[..<first])
        let suffix = String(chars[(last + 1)...])
        let core = chars[first...last]
        var decimals = 0
        if let dot = core.firstIndex(of: ".") {
            decimals = core[(dot + 1)...].filter { $0 == "0" || $0 == "#" }.count
        }
        return NumberSection(
            prefix: prefix,
            suffix: suffix,
            decimals: decimals,
            grouping: core.contains(",")
        )
    }

    private static func formatNumber(_ value: Double, pattern: String) -> String? {
        guard value.isFinite else { return nil }
        let parts = pattern.components(separatedBy: ";")
        guard let positive = parseSection(parts[0]) else { return nil }
        let negativeSection = parts.count > 1 ? parseSection(parts[1]) : nil

        let magnitude = abs(value)
        let positiveBody = String(format: "%.\(positive.decimals)f", magnitude)
        // A value that rounds to zero is not shown as negative.
        let isNegative = value < 0 && (Double(positiveBody) ?? 0) != 0

        let section = (isNegative ? negativeSection : nil) ?? positive
        var body = section.decimals == positive.decimals
            ? positiveBody
            : String(format: "%.\(section.decimals)f", magnitude)
        if section.grouping {
            body = group(body)
        }
        let sign = (isNegative && negativeSection == nil) ? "-" : ""
        return sign + section.prefix + body + section.suffix
    }

    private static func group(_ body: String) -> String {
        let pieces = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let integerPart = String(pieces[0])
        var grouped = ""
        for (offset, character) in integerPart.reversed().enumerated() {
            if offset > 0, offset % 3 == 0 {
                grouped.append(",")
            }
            grouped.append(character)
        }
        let integerGrouped = String(grouped.reversed())
        if pieces.count > 1 {
            return integerGrouped + "." + String(pieces[1])
        }
        return integerGrouped
    }

    // MARK: - ago

    private static func ago(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86_400))d ago"
    }
}
