import SwiftUI
import WidgetSpec

/// Draws a render tree with native SwiftUI views. It cannot fetch, evaluate or run anything;
/// actions are handed to the host.
public struct WidgetView: View {
    private let node: RenderNode
    private let accent: Color
    private let onAction: (RenderAction) -> Void

    /// `accent` is what the "accent" colour token means for this widget.
    public init(node: RenderNode, accent: Color = .accentColor, onAction: @escaping (RenderAction) -> Void) {
        self.node = node
        self.accent = accent
        self.onAction = onAction
    }

    public var body: some View {
        NodeView(node: node, accent: accent, onAction: onAction)
    }
}

private struct NodeView: View {
    let node: RenderNode
    let accent: Color
    let onAction: (RenderAction) -> Void

    var body: some View {
        styled
    }

    @ViewBuilder
    private var styled: some View {
        let view = content
            .padding(CGFloat(node.padding ?? 0))
            .background(node.background.map { $0.style(accent: accent) } ?? AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: CGFloat(node.radius ?? 0)))
        if let action = node.action, node.kind != .button {
            Button { onAction(action) } label: { view.contentShape(Rectangle()) }
                .buttonStyle(.plain)
        } else {
            view
        }
    }

    @ViewBuilder
    private var content: some View {
        switch node.kind {
        case .vstack:
            VStack(alignment: horizontal, spacing: node.spacing.map { CGFloat($0) }) { children }
                .frame(maxWidth: .infinity, alignment: frameAlignment)
        case .hstack:
            HStack(alignment: .firstTextBaseline, spacing: node.spacing.map { CGFloat($0) }) { children }
        case .zstack:
            ZStack(alignment: frameAlignment) { children }
        case .spacer:
            Spacer(minLength: 0)
        case .divider:
            Divider()
        case .text:
            Text(node.text ?? "")
                .font(font)
                .foregroundStyle(node.color?.style(accent: accent) ?? AnyShapeStyle(.primary))
                .lineLimit(node.lines)
                .multilineTextAlignment(textAlignment)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
        case .icon:
            Image(systemName: node.symbol ?? "questionmark")
                .font(font)
                .foregroundStyle(node.color?.style(accent: accent) ?? AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
        case .badge:
            Text(node.text ?? "")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        case .button:
            Button(node.text ?? "") {
                if let action = node.action { onAction(action) }
            }
        }
    }

    @ViewBuilder
    private var children: some View {
        ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
            NodeView(node: child, accent: accent, onAction: onAction)
        }
    }

    private var font: Font {
        let base: Font = switch node.size {
        case .caption: .caption
        case .title: .title3
        case .display: .largeTitle
        case .body, nil: .callout
        }
        let weight: Font.Weight = switch node.weight {
        case .light: .light
        case .medium: .medium
        case .bold: .bold
        case .regular, nil: .regular
        }
        return base.weight(weight)
    }

    private var horizontal: HorizontalAlignment {
        switch node.align {
        case .center: .center
        case .trailing: .trailing
        case .leading, nil: .leading
        }
    }

    private var frameAlignment: Alignment {
        switch node.align {
        case .center: .center
        case .trailing: .trailing
        case .leading, nil: .leading
        }
    }

    private var textAlignment: TextAlignment {
        switch node.align {
        case .center: .center
        case .trailing: .trailing
        case .leading, nil: .leading
        }
    }
}

extension RenderColor {
    /// Primary and secondary are hierarchical, so the host decides what they look like (white on a
    /// tinted widget, for example) without the widget file knowing.
    func style(accent: Color) -> AnyShapeStyle {
        switch self {
        case .primary: AnyShapeStyle(.primary)
        case .secondary: AnyShapeStyle(.secondary)
        case .accent: AnyShapeStyle(accent)
        case .positive: AnyShapeStyle(Color.green)
        case .negative: AnyShapeStyle(Color.red)
        case .rgb(let red, let green, let blue): AnyShapeStyle(Color(red: red, green: green, blue: blue))
        }
    }
}
