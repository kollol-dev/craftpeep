import AppKit
import Foundation
import Intelligence
import UserNotifications

/// The daily trending alert's settings. Which sources count is stored with each source, not here.
nonisolated enum AlertPreferences {
    static let enabledKey = "alerts.enabled"
    static let hourKey = "alerts.hour"
    static let minuteKey = "alerts.minute"
    static let strictnessKey = "alerts.strictness"
    static let lastRunKey = "alerts.lastRun"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static var schedule: DailyAlertSchedule {
        let defaults = UserDefaults.standard
        return DailyAlertSchedule(
            hour: defaults.object(forKey: hourKey) as? Int ?? 10,
            minute: defaults.object(forKey: minuteKey) as? Int ?? 0
        )
    }

    static var strictness: AlertStrictness {
        AlertStrictness(rawValue: UserDefaults.standard.string(forKey: strictnessKey) ?? "") ?? .strong
    }

    /// When the alert last ran, whether or not it found anything.
    static var lastRun: Date? {
        get { UserDefaults.standard.object(forKey: lastRunKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastRunKey) }
    }
}

/// Posts alert notifications and routes a click back to the story.
final class AlertNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let clusterKey = "clusterID"
    static let urlKey = "url"

    /// Called on the main actor with the story a notification was for.
    var onOpen: (@MainActor (Int64, String?) -> Void)?

    override init() {
        super.init()
        // Set before the app finishes launching, so a click that launches the app is still delivered.
        UNUserNotificationCenter.current().delegate = self
    }

    /// Asks once; afterwards macOS remembers the answer and only System Settings can change it.
    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    func post(title: String, body: String, clusterID: Int64?, url: String?) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var info: [String: Any] = [:]
        if let clusterID { info[Self.clusterKey] = clusterID }
        if let url { info[Self.urlKey] = url }
        content.userInfo = info
        let request = UNNotificationRequest(identifier: "trending-\(UUID().uuidString)", content: content, trigger: nil)
        try await UNUserNotificationCenter.current().add(request)
    }

    static func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // Show the banner even when CraftPeep is the frontmost app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let clusterID = (info[Self.clusterKey] as? NSNumber)?.int64Value else { return }
        let url = info[Self.urlKey] as? String
        await MainActor.run { self.onOpen?(clusterID, url) }
    }
}
