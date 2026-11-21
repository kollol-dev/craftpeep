import AppKit
import Domain
import SwiftUI
import WidgetBuilder
import WidgetRender
import WidgetRuntime
import WidgetSpec

/// What a desktop widget is showing. Every state is drawn; none is a blank box.
enum DesktopWidgetState: Equatable {
    case loading
    /// `unread` counts unread stories shown, for the header badge.
    case ready(RenderNode, asOf: Date?, unread: Int)
    case empty(String)
    case failed(String)
}

/// One widget on the desktop: where and how the user set it up, what it is, and what it shows now.
struct DesktopWidgetItem: Identifiable, Equatable {
    var instance: WidgetInstance
    let definition: WidgetDefinition
    var state: DesktopWidgetState

    var id: String { instance.id }
    var size: WidgetSize { WidgetSize(rawValue: instance.size) ?? .medium }
    var appearance: WidgetAppearance { WidgetAppearance(instance) }
}

// MARK: - Appearance

/// How a widget is drawn, chosen per widget, in the spirit of the system's own widget styles.
enum WidgetStyle: String, CaseIterable, Identifiable {
    /// Translucent, following the Mac's light or dark appearance.
    case automatic
    case light
    case dark
    /// Mostly see-through, letting the wallpaper show.
    case clear
    /// Filled with the widget's colour.
    case tinted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        case .clear: "Clear"
        case .tinted: "Tinted"
        }
    }
}

enum WidgetTint: String, CaseIterable, Identifiable {
    case blue, indigo, purple, pink, red, orange, yellow, green, teal, graphite

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .graphite: Color(white: 0.45)
        }
    }
}

struct WidgetAppearance: Equatable {
    var style: WidgetStyle
    var tint: WidgetTint

    static let standard = WidgetAppearance(style: .automatic, tint: .blue)

    init(style: WidgetStyle, tint: WidgetTint) {
        self.style = style
        self.tint = tint
    }

    /// Unknown stored values fall back to the defaults rather than failing.
    init(_ instance: WidgetInstance) {
        style = WidgetStyle(rawValue: instance.style) ?? .automatic
        tint = WidgetTint(rawValue: instance.tint) ?? .blue
    }

    /// Light, dark and tinted widgets look the same whatever the Mac is set to; the others follow it.
    var colorScheme: ColorScheme? {
        switch style {
        case .light: .light
        case .dark, .tinted: .dark
        case .automatic, .clear: nil
        }
    }

    /// What the widget file's "accent" colour means here. On a tinted widget the tint is the background,
    /// so headings turn white; on a light one, yellow is deepened so it stays readable.
    var accent: Color {
        switch style {
        case .tinted: .white
        case .light where tint == .yellow: tint.color.mix(with: .black, by: 0.3)
        default: tint.color
        }
    }

    @ViewBuilder
    var background: some View {
        let shape = RoundedRectangle(cornerRadius: DesktopWidgetContent.cornerRadius, style: .continuous)
        switch style {
        case .automatic:
            shape.fill(.regularMaterial)
        case .light:
            shape.fill(Color(white: 0.98))
        case .dark:
            shape.fill(Color(white: 0.11))
        case .clear:
            shape.fill(.ultraThinMaterial.opacity(0.55))
        case .tinted:
            shape.fill(LinearGradient(
                colors: [tint.color.mix(with: .white, by: 0.12), tint.color.mix(with: .black, by: 0.22)],
                startPoint: .top, endPoint: .bottom
            ))
        }
    }
}

extension WidgetSize {
    var contentSize: NSSize {
        switch self {
        case .small: NSSize(width: 300, height: 190)
        case .medium: NSSize(width: 340, height: 400)
        case .large: NSSize(width: 380, height: 620)
        }
    }

    var label: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}

/// A widget the AI builder suggested, waiting for the user to accept or discard it.
struct WidgetSuggestion: Equatable {
    let proposal: WidgetProposal
    let definition: WidgetDefinition
    let preview: DesktopWidgetState
    /// The widget this would change, when the request was an edit.
    let replacing: String?
}

/// Owns the desktop-level windows, one per widget. These are ordinary AppKit windows placed just above
/// the desktop icons and below every normal window; they are not system (WidgetKit) widgets.
final class DesktopWidgetController: NSObject, NSWindowDelegate {
    private var panels: [String: NSPanel] = [:]
    private var sizes: [String: WidgetSize] = [:]
    private weak var model: AppModel?

    func sync(model: AppModel, items: [DesktopWidgetItem]) {
        self.model = model
        let wanted = Set(items.map(\.id))
        for (id, panel) in panels where !wanted.contains(id) {
            panel.orderOut(nil)
            panels[id] = nil
            sizes[id] = nil
        }
        for (index, item) in items.enumerated() {
            if let panel = panels[item.id] {
                if sizes[item.id] != item.size {
                    // Keep the top-left corner where the user put it when the size changes.
                    let top = panel.frame.maxY
                    panel.setContentSize(item.size.contentSize)
                    panel.setFrameTopLeftPoint(NSPoint(x: panel.frame.minX, y: top))
                }
            } else {
                let panel = makePanel(model: model, item: item, index: index)
                panels[item.id] = panel
                panel.orderFront(nil)
            }
            sizes[item.id] = item.size
        }
    }

    private func makePanel(model: AppModel, item: DesktopWidgetItem, index: Int) -> NSPanel {
        let size = item.size.contentSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        // On every Space, left alone by Mission Control, and not part of window cycling.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: DesktopWidgetView(model: model, instanceID: item.id))
        panel.setFrameOrigin(Self.origin(for: item.instance, size: size, index: index))
        panel.delegate = self
        return panel
    }

    func windowDidMove(_ notification: Notification) {
        guard let moved = notification.object as? NSPanel,
              let id = panels.first(where: { $0.value === moved })?.key else { return }
        let origin = moved.frame.origin
        Task { await model?.widgetMoved(id, to: origin) }
    }

    /// The saved position if it is still on a connected screen; otherwise the top-right of the main
    /// screen, stepped down and left for each further widget so new ones do not hide each other.
    static func origin(for instance: WidgetInstance, size: NSSize, index: Int) -> NSPoint {
        if let x = instance.x, let y = instance.y {
            let frame = NSRect(x: x, y: y, width: size.width, height: size.height)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame.insetBy(dx: 40, dy: 40)) }) {
                return frame.origin
            }
        }
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let step = CGFloat(index % 6) * 28
        return NSPoint(x: visible.maxX - size.width - 24 - step, y: visible.maxY - size.height - 24 - step)
    }
}

/// What the frame around a widget shows at the top: its symbol, its title and, for widgets that can show
/// different lists, a menu to switch between them.
struct WidgetHeader {
    var title: String
    var symbol: String
    /// Empty for widgets with nothing to switch.
    var options: [(id: String, label: String)] = []
    var selected: String?
    var onSelect: (String) -> Void = { _ in }
    var onSettings: (() -> Void)?
}

/// A widget on the desktop, with a menu for the things a user does to it.
struct DesktopWidgetView: View {
    let model: AppModel
    let instanceID: String
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let item = model.widgets.first { $0.id == instanceID }
        DesktopWidgetContent(
            state: item?.state ?? .loading,
            name: item?.definition.name ?? "Widget",
            appearance: item?.appearance ?? .standard,
            header: item.map(header)
        ) { model.perform($0) }
            .contextMenu {
                if let item, item.definition.hasViewSetting {
                    Menu("Show") {
                        ForEach(model.widgetViewOptions, id: \.id) { option in
                            Toggle(option.label, isOn: Binding(
                                get: { item.currentView == option.id },
                                set: { if $0 { Task { await model.setWidgetSetting(instanceID, key: "view", value: .string(option.id)) } } }
                            ))
                        }
                    }
                }
                Menu("Appearance") {
                    ForEach(WidgetStyle.allCases) { style in
                        Toggle(style.label, isOn: Binding(
                            get: { item?.appearance.style == style },
                            set: { if $0 { Task { await model.setWidgetAppearance(instanceID, style: style) } } }
                        ))
                    }
                }
                Menu("Colour") {
                    ForEach(WidgetTint.allCases) { tint in
                        Toggle(tint.label, isOn: Binding(
                            get: { item?.appearance.tint == tint },
                            set: { if $0 { Task { await model.setWidgetAppearance(instanceID, tint: tint) } } }
                        ))
                    }
                }
                Menu("Size") {
                    ForEach([WidgetSize.small, .medium, .large], id: \.self) { size in
                        Toggle(size.label, isOn: Binding(
                            get: { item?.size == size },
                            set: { if $0 { Task { await model.setWidgetSize(instanceID, size) } } }
                        ))
                    }
                }
                Button("Widget Settings…") { showSettings() }
                Divider()
                Button("Remove from Desktop", role: .destructive) {
                    Task { await model.removeWidget(instanceID) }
                }
            }
    }

    private func showSettings() {
        NSApp.activate()
        openSettings()
    }

    private func header(_ item: DesktopWidgetItem) -> WidgetHeader {
        let symbol = item.definition.symbol ?? "square.grid.2x2.fill"
        guard item.definition.hasViewSetting else {
            return WidgetHeader(title: item.definition.name, symbol: symbol, onSettings: showSettings)
        }
        return WidgetHeader(
            title: WidgetViews.label(for: item.currentView),
            symbol: item.currentView.hasPrefix("folder:") ? "folder.fill" : symbol,
            options: model.widgetViewOptions,
            selected: item.currentView,
            onSelect: { id in Task { await model.setWidgetSetting(instanceID, key: "view", value: .string(id)) } },
            onSettings: showSettings
        )
    }
}

extension WidgetDefinition {
    /// Widgets whose file declares a "view" setting can be switched between lists from their header.
    var hasViewSetting: Bool { settings?.contains { $0.key == "view" } == true }
}

extension DesktopWidgetItem {
    var currentView: String {
        if case .string(let view)? = instance.settings["view"], !view.isEmpty { return view }
        return "overview"
    }
}

/// On a coloured background the system's label colours are translucent and wash out; use solid white
/// and two steps of it instead.
private struct TintedText: ViewModifier {
    let isTinted: Bool

    func body(content: Content) -> some View {
        if isTinted {
            content.foregroundStyle(.white, .white.opacity(0.8), .white.opacity(0.62))
        } else {
            content
        }
    }
}

/// Draws a widget inside the standard frame: header, content and footer. Used on the desktop and for previews.
struct DesktopWidgetContent: View {
    /// The system's widgets use a large, continuous corner; matching it is most of what makes one feel native.
    static let cornerRadius: CGFloat = 22

    let state: DesktopWidgetState
    let name: String
    var appearance: WidgetAppearance = .standard
    var header: WidgetHeader?
    let perform: (RenderAction) -> Void

    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            if let header { headerBar(header) }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .mask(fadeAtBottom)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { backdrop }
        .clipShape(shape)
        .overlay(shape.strokeBorder(edgeHighlight, lineWidth: 1))
        .modifier(TintedText(isTinted: appearance.style == .tinted))
        .environment(\.colorScheme, appearance.colorScheme ?? systemScheme)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(header?.title ?? name) widget")
    }

    // MARK: Frame

    /// The style's background, with a soft glow of the widget's colour from the top corner.
    @ViewBuilder
    private var backdrop: some View {
        ZStack {
            appearance.background
            switch appearance.style {
            case .tinted:
                LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center)
            case .light:
                RadialGradient(colors: [appearance.tint.color.opacity(0.10), .clear], center: .topLeading, startRadius: 0, endRadius: 280)
            default:
                RadialGradient(colors: [appearance.tint.color.opacity(0.24), .clear], center: .topLeading, startRadius: 0, endRadius: 300)
            }
        }
    }

    /// A light top edge and a faint lower one, which reads as glass rather than a flat card.
    private var edgeHighlight: LinearGradient {
        let top: Color = appearance.style == .light ? .black.opacity(0.06) : .white.opacity(appearance.style == .tinted ? 0.35 : 0.16)
        let bottom: Color = appearance.style == .light ? .black.opacity(0.10) : .white.opacity(0.04)
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    /// Long lists fade out instead of being cut off mid-line.
    private var fadeAtBottom: LinearGradient {
        LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }

    private func headerBar(_ header: WidgetHeader) -> some View {
        HStack(spacing: 9) {
            iconTile(header.symbol)
            if header.options.isEmpty {
                Text(header.title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .lineLimit(1)
            } else {
                Menu {
                    ForEach(header.options, id: \.id) { option in
                        Button {
                            header.onSelect(option.id)
                        } label: {
                            if option.id == header.selected { Label(option.label, systemImage: "checkmark") } else { Text(option.label) }
                        }
                        if option.id == "saved", header.options.count > 4 { Divider() }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(header.title)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
                .help("Choose what this widget shows")
                .accessibilityLabel("Showing \(header.title). Choose what this widget shows")
            }
            Spacer(minLength: 4)
            if case .ready(_, _, let unread) = state, unread > 0 {
                Text("\(unread) new")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(appearance.style == .tinted ? appearance.tint.color : .white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(appearance.style == .tinted ? AnyShapeStyle(.white) : AnyShapeStyle(appearance.accent.gradient), in: Capsule())
                    .accessibilityLabel("\(unread) unread")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 2)
    }

    /// A small app-icon-like tile: the widget's colour with a white symbol.
    private func iconTile(_ symbol: String) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(appearance.style == .tinted
                  ? AnyShapeStyle(.white.opacity(0.22))
                  : AnyShapeStyle(LinearGradient(colors: [appearance.tint.color.mix(with: .white, by: 0.15), appearance.tint.color.mix(with: .black, by: 0.15)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
            .frame(width: 24, height: 24)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: appearance.tint.color.opacity(appearance.style == .tinted ? 0 : 0.35), radius: 3, y: 1)
            .accessibilityHidden(true)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready(let node, _, _):
            WidgetView(node: node, accent: appearance.accent, onAction: perform)
        case .empty(let text):
            message(text, symbol: "tray")
        case .failed(let reason):
            message(reason, symbol: "exclamationmark.triangle")
        }
    }

    private func message(_ text: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Freshness is always stated, and old data says that it is old. Refresh and Settings sit beside it.
    private var footer: some View {
        HStack(spacing: 10) {
            if case .ready(_, let asOf, _) = state {
                let stale = asOf.map { $0.timeIntervalSinceNow < -8 * 3600 } ?? true
                Text(asOf.map { (stale ? "Not updated since " : "Updated ") + $0.relative } ?? "Never updated")
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(stale ? .secondary : .tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            footerButton("arrow.clockwise", help: "Refresh") { perform(.refresh) }
            if let onSettings = header?.onSettings {
                footerButton("gearshape", help: "Widget settings", action: onSettings)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .padding(.top, 4)
    }

    private func footerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(.quaternary.opacity(0.6), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
