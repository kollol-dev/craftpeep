import AppKit
import SwiftUI
import WidgetRender
import WidgetSpec

/// What the desktop widget is showing. Every state is drawn; none is a blank box.
enum DesktopWidgetState: Equatable {
    case loading
    case ready(RenderNode, asOf: Date?)
    case empty
    case failed(String)
}

/// The user's choices for the desktop widget. One widget for now, so these live in preferences.
nonisolated struct WidgetPreferences: Equatable {
    static let enabledKey = "widget.newsList.enabled"
    static let sizeKey = "widget.newsList.size"
    static let subjectKey = "widget.newsList.subject"
    static let showSourcesKey = "widget.newsList.showSources"
    static let originKey = "widget.newsList.origin"

    /// Set by the debug snapshot mode so the widget can be drawn in an ordinary window without
    /// putting it on the desktop.
    nonisolated(unsafe) static var alwaysResolve = false

    var isEnabled: Bool
    var size: WidgetSize
    var subject: String
    var showSources: Bool

    static func current() -> WidgetPreferences {
        let defaults = UserDefaults.standard
        return WidgetPreferences(
            isEnabled: defaults.bool(forKey: enabledKey),
            size: WidgetSize(rawValue: defaults.string(forKey: sizeKey) ?? "") ?? .medium,
            subject: defaults.string(forKey: subjectKey) == "ai" ? "ai" : "all",
            showSources: defaults.object(forKey: showSourcesKey) as? Bool ?? true
        )
    }

    var contentSize: NSSize {
        switch size {
        case .small: NSSize(width: 300, height: 190)
        case .medium: NSSize(width: 340, height: 400)
        case .large: NSSize(width: 380, height: 620)
        }
    }
}

/// Owns the desktop-level window. This is an ordinary AppKit window placed just above the desktop icons
/// and below every normal window; it is not a system (WidgetKit) widget.
final class DesktopWidgetController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var shown: WidgetPreferences?

    func sync(model: AppModel, preferences: WidgetPreferences) {
        guard preferences.isEnabled else {
            panel?.orderOut(nil)
            panel = nil
            shown = nil
            return
        }
        if panel == nil {
            panel = makePanel(model: model, size: preferences.contentSize)
        } else if shown?.size != preferences.size, let panel {
            // Keep the top-left corner where the user put it when the size changes.
            let top = panel.frame.maxY
            panel.setContentSize(preferences.contentSize)
            panel.setFrameTopLeftPoint(NSPoint(x: panel.frame.minX, y: top))
        }
        shown = preferences
        panel?.orderFront(nil)
    }

    private func makePanel(model: AppModel, size: NSSize) -> NSPanel {
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
        panel.contentView = NSHostingView(rootView: DesktopWidgetView(model: model))
        panel.setFrameOrigin(Self.restoredOrigin(for: size))
        panel.delegate = self
        return panel
    }

    func windowDidMove(_ notification: Notification) {
        guard let frame = panel?.frame else { return }
        UserDefaults.standard.set("\(Int(frame.minX)),\(Int(frame.minY))", forKey: WidgetPreferences.originKey)
    }

    /// The saved position if it is still on a connected screen, otherwise the top-right of the main one.
    static func restoredOrigin(for size: NSSize) -> NSPoint {
        let parts = (UserDefaults.standard.string(forKey: WidgetPreferences.originKey) ?? "").split(separator: ",").compactMap { Double($0) }
        if parts.count == 2 {
            let frame = NSRect(x: parts[0], y: parts[1], width: size.width, height: size.height)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame.insetBy(dx: 40, dy: 40)) }) {
                return frame.origin
            }
        }
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: visible.maxX - size.width - 24, y: visible.maxY - size.height - 24)
    }
}

struct DesktopWidgetView: View {
    let model: AppModel

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
        .accessibilityLabel("CraftPeep news widget")
    }

    @ViewBuilder
    private var content: some View {
        switch model.widget {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready(let node, _):
            WidgetView(node: node) { model.perform($0) }
        case .empty:
            message("No stories in the last three days.", symbol: "newspaper")
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
        if case .ready(_, let asOf) = model.widget {
            let stale = asOf.map { $0.timeIntervalSinceNow < -2 * 3600 } ?? true
            Text(asOf.map { (stale ? "Not updated since " : "Updated ") + $0.relative } ?? "Never updated")
                .font(.caption2)
                .foregroundStyle(stale ? .secondary : .tertiary)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
    }
}
