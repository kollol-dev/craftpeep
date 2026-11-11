#if DEBUG
import AppKit
import SwiftUI

/// Development aid: lets a build photograph its own windows so the UI can be checked without
/// screen-recording permission. Does nothing unless CRAFTPEEP_SNAPSHOT is set. Not compiled into Release.
///
///   open --env CRAFTPEEP_SNAPSHOT=overview,select CraftPeep.app
///
/// Options: a section name (overview, ai, news, saved), `select` to select the first story,
/// `panels` to also show Settings and the menu bar panel in plain windows so they can be captured.
/// PNGs are written to the app's Application Support/CraftPeep/snapshots.
/// Translucent chrome (sidebar, toolbar buttons) comes out blank; that is a limit of the capture.
enum DebugSnapshot {
    static func scheduleIfRequested(model: AppModel) {
        guard let value = ProcessInfo.processInfo.environment["CRAFTPEEP_SNAPSHOT"] else { return }
        let options = Set(value.split(separator: ",").map(String.init))

        Task {
            try? await Task.sleep(for: .seconds(4))
            if let section = SidebarSection.allCases.first(where: { options.contains($0.rawValue) }) {
                model.section = section
            }
            try? await Task.sleep(for: .seconds(1))
            if options.contains("select") { model.selection = model.stories.first?.id }
            if options.contains("panels") {
                show(SettingsView(model: model), title: "Settings", size: NSSize(width: 640, height: 480))
                show(PulseView(model: model), title: "Pulse", size: NSSize(width: 360, height: 420))
            }
            try? await Task.sleep(for: .seconds(2))
            capture()
        }
    }

    private static var extraWindows: [NSWindow] = []

    private static func show(_ view: some View, title: String, size: NSSize) {
        // A fixed-size window with a plain hosting view. Letting the hosting controller size the
        // window from a TabView raised a layout exception.
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = title
        window.contentView = hosting
        window.orderFront(nil)
        extraWindows.append(window)
    }

    private static func capture() {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return }
        let directory = base.appendingPathComponent("CraftPeep/snapshots", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (index, window) in NSApp.windows.enumerated() where window.isVisible {
            // The frame view includes the title bar and toolbar; contentView alone does not.
            guard let view = window.contentView?.superview ?? window.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let name = "\(index)-\(window.title.isEmpty ? "untitled" : window.title).png"
            try? bitmap.representation(using: .png, properties: [:])?
                .write(to: directory.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-")))
        }
    }
}
#endif
