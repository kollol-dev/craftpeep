import Foundation
import WidgetExpr
import WidgetSpec

/// What to draw, with every expression already evaluated. Building this is pure, so it can be tested
/// without a screen; the SwiftUI layer only maps it to views.
public struct RenderNode: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case vstack, hstack, zstack, spacer, divider, text, icon, badge, button
    }

    public var kind: Kind
    public var children: [RenderNode] = []
    public var text: String?
    public var symbol: String?
    public var size: WidgetTextSize?
    public var weight: WidgetFontWeight?
    public var color: RenderColor?
    public var background: RenderColor?
    public var align: WidgetAlignment?
    public var spacing: Double?
    public var padding: Double?
    public var radius: Double?
    public var lines: Int?
    public var action: RenderAction?
    public var width: Double?
    public var height: Double?
    public var design: String?

    public init(kind: Kind) {
        self.kind = kind
    }
}

public enum RenderColor: Sendable, Equatable {
    case primary, secondary, accent, positive, negative
    case rgb(red: Double, green: Double, blue: Double)

    /// A token name or a #RRGGBB value. Anything else is no colour, which falls back to the default.
    public init?(_ string: String) {
        switch string.lowercased() {
        case "primary": self = .primary
        case "secondary": self = .secondary
        case "accent": self = .accent
        case "positive": self = .positive
        case "negative": self = .negative
        default:
            let hex = string.hasPrefix("#") ? String(string.dropFirst()) : ""
            guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
            self = .rgb(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
        }
    }
}

/// Something a widget asks the host to do. The host decides whether to do it.
public enum RenderAction: Sendable, Equatable {
    case openURL(String)
    case copy(String)
    case refresh
}

public struct RenderResult: Sendable, Equatable {
    public var root: RenderNode?
    public var issues: [String]
}

public enum RenderTree {
    /// Upper bounds, so no widget file can ask for an unreasonable amount of drawing.
    static let maximumNodes = 600
    static let maximumListItems = 50
    static let maximumTextLength = 500

    public static func build(
        _ definition: WidgetDefinition,
        size: WidgetSize,
        scope: ExprScope,
        context: ExprContext = ExprContext()
    ) -> RenderResult {
        guard let component = definition.view[size.rawValue] ?? definition.view["default"] else {
            return RenderResult(root: nil, issues: ["the widget has no view"])
        }
        var builder = Builder(context: context)
        let root = builder.build(component, scope: scope)
        return RenderResult(root: root, issues: builder.issues)
    }

    private struct Builder {
        let context: ExprContext
        var issues: [String] = []
        var count = 0

        mutating func evaluate(_ template: String, _ scope: ExprScope) -> ExprValue? {
            do {
                return try Template.parse(template).evaluate(in: scope, context: context)
            } catch {
                if issues.count < 10 { issues.append("could not evaluate '\(template.prefix(60))': \(error)") }
                return nil
            }
        }

        mutating func string(_ template: String?, _ scope: ExprScope) -> String? {
            guard let template, let value = evaluate(template, scope) else { return nil }
            return String(value.displayString.prefix(RenderTree.maximumTextLength))
        }

        mutating func build(_ component: WidgetComponent, scope: ExprScope) -> RenderNode? {
            guard count < RenderTree.maximumNodes else { return nil }
            if let condition = component.when {
                guard evaluate(condition, scope)?.isTruthy == true else { return nil }
            }
            count += 1

            var node: RenderNode
            switch component.type {
            case .vstack: node = RenderNode(kind: .vstack)
            case .hstack: node = RenderNode(kind: .hstack)
            case .zstack: node = RenderNode(kind: .zstack)
            case .spacer: return RenderNode(kind: .spacer)
            case .divider: return RenderNode(kind: .divider)
            case .text, .badge, .button:
                guard let text = string(component.text, scope), !text.isEmpty else { return nil }
                node = RenderNode(kind: component.type == .text ? .text : component.type == .badge ? .badge : .button)
                node.text = text
            case .number:
                guard let text = number(component, scope) else { return nil }
                node = RenderNode(kind: .text)
                node.text = text
            case .icon:
                guard let symbol = string(component.symbol, scope), !symbol.isEmpty else { return nil }
                node = RenderNode(kind: .icon)
                node.symbol = symbol
            case .list:
                node = RenderNode(kind: .vstack)
                node.children = listItems(component, scope: scope)
            case .image, .progress, .chart:
                // In the vocabulary, not drawn yet. Left out rather than faked.
                if issues.count < 10 { issues.append("'\(component.type.rawValue)' is not drawn in this version") }
                return nil
            }

            if component.type != .list {
                for child in component.children ?? [] {
                    if let built = build(child, scope: scope) { node.children.append(built) }
                }
            }

            node.size = component.size
            node.weight = component.weight
            node.color = string(component.color, scope).flatMap(RenderColor.init)
            node.background = string(component.background, scope).flatMap(RenderColor.init)
            node.align = component.align
            node.spacing = component.spacing.map { min(max($0, 0), 64) }
            node.padding = component.padding.map { min(max($0, 0), 64) }
            node.radius = component.radius.map { min(max($0, 0), 64) }
            node.lines = component.lines.map { min(max($0, 1), 20) }
            node.width = component.width.map { min(max($0, 0), 600) }
            node.height = component.height.map { min(max($0, 0), 600) }
            node.design = component.design
            node.action = action(component.action, scope)
            return node
        }

        mutating func listItems(_ component: WidgetComponent, scope: ExprScope) -> [RenderNode] {
            guard let each = component.each, let item = component.item?.value,
                  case .array(let elements)? = evaluate(each, scope) else { return [] }
            let limit = min(component.limit ?? RenderTree.maximumListItems, RenderTree.maximumListItems)
            let name = component.loopVariable ?? "item"
            var built: [RenderNode] = []
            // "index" is the element's position from 0, so a widget can style the first row differently.
            for (index, element) in elements.prefix(max(limit, 0)).enumerated() {
                let itemScope = scope.adding(name, element).adding("index", .number(Double(index)))
                if let node = build(item, scope: itemScope) { built.append(node) }
            }
            return built
        }

        mutating func number(_ component: WidgetComponent, _ scope: ExprScope) -> String? {
            let value: ExprValue?
            switch component.value {
            case .number(let literal)?: value = .number(literal)
            case .string(let template)?: value = evaluate(template, scope)
            default: value = nil
            }
            guard let value, value != .null else { return nil }
            guard let pattern = component.format else { return value.displayString }
            let formatted = evaluate("{{ format(__value, __pattern) }}", scope.adding("__value", value).adding("__pattern", .string(pattern)))
            return formatted?.displayString
        }

        mutating func action(_ action: WidgetAction?, _ scope: ExprScope) -> RenderAction? {
            guard let action else { return nil }
            switch action.type {
            case .refresh: return .refresh
            case .copy: return string(action.value, scope).map(RenderAction.copy)
            case .openURL:
                // Only web links ever leave a widget. The host checks again before opening.
                guard let value = string(action.value, scope), let url = URL(string: value),
                      let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.host() != nil
                else { return nil }
                return .openURL(value)
            }
        }
    }
}
