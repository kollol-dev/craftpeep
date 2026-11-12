import AppKit
import Domain
import SwiftUI
import WidgetBuilder
import WidgetRender
import WidgetSpec

/// What a desktop widget is showing. Every state is drawn; none is a blank box.
enum DesktopWidgetState: Equatable {
    case loading
    case ready(RenderNode, asOf: Date?)
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

/// A widget on the desktop, with a menu for the things a user does to it.
struct DesktopWidgetView: View {
    let model: AppModel
    let instanceID: String
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let item = model.widgets.first { $0.id == instanceID }
        DesktopWidgetContent(state: item?.state ?? .loading, name: item?.definition.name ?? "Widget") { model.perform($0) }
            .contextMenu {
                Menu("Size") {
                    ForEach([WidgetSize.small, .medium, .large], id: \.self) { size in
                        Toggle(size.label, isOn: Binding(
                            get: { item?.size == size },
                            set: { if $0 { Task { await model.setWidgetSize(instanceID, size) } } }
                        ))
                    }
                }
                Button("Widget Settings…") {
                    NSApp.activate()
                    openSettings()
                }
                Divider()
                Button("Remove from Desktop", role: .destructive) {
                    Task { await model.removeWidget(instanceID) }
                }
            }
    }
}

/// Draws a widget's current state inside the standard widget chrome. Used on the desktop and for previews.
struct DesktopWidgetContent: View {
    let state: DesktopWidgetState
    let name: String
    let perform: (RenderAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name) widget")
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready(let node, _):
            WidgetView(node: node, onAction: perform)
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

    /// Freshness is always stated, and old data says that it is old.
    @ViewBuilder
    private var footer: some View {
        if case .ready(_, let asOf) = state {
            let stale = asOf.map { $0.timeIntervalSinceNow < -8 * 3600 } ?? true
            Text(asOf.map { (stale ? "Not updated since " : "Updated ") + $0.relative } ?? "Never updated")
                .font(.caption2)
                .foregroundStyle(stale ? .secondary : .tertiary)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
    }
}
