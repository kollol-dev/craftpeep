import Foundation
import Observation
import Sparkle

/// Wraps Sparkle's standard updater so the app's views never touch Sparkle directly.
///
/// The feed URL and public signing key come from the app's Info.plist (`SUFeedURL`, `SUPublicEDKey`),
/// so moving the feed to a website later is an Info.plist change. Every update must carry a valid EdDSA
/// signature from the release key, which lives only in the publisher's Keychain.
@MainActor
@Observable
public final class AppUpdater {
    public private(set) var canCheckForUpdates = false

    /// False when the bundle has no feed configured (for example a debug build run from Xcode with the
    /// key stripped); the menu item and setting then hide rather than fail.
    public let isConfigured: Bool

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?

    public init(bundle: Bundle = .main) {
        let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        isConfigured = !(feed ?? "").isEmpty && !(key ?? "").isEmpty
        controller = SPUStandardUpdaterController(
            startingUpdater: isConfigured, updaterDelegate: nil, userDriverDelegate: nil
        )
        // Sparkle changes this property on the main thread, so the observer runs there too.
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let value = change.newValue ?? false
            MainActor.assumeIsolated { self?.canCheckForUpdates = value }
        }
    }

    public func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Daily background checks. Sparkle stores this itself in the app's preferences.
    public var automaticallyChecksForUpdates: Bool {
        get {
            access(keyPath: \.automaticallyChecksForUpdates)
            return controller.updater.automaticallyChecksForUpdates
        }
        set {
            withMutation(keyPath: \.automaticallyChecksForUpdates) {
                controller.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    public var currentVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
