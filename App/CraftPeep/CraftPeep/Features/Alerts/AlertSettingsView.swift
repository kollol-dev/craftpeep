import Domain
import Intelligence
import SwiftUI

/// Settings → Alerts: the once-a-day notification for very trending stories.
struct AlertSettingsView: View {
    let model: AppModel

    @AppStorage(AlertPreferences.enabledKey) private var enabled = false
    @AppStorage(AlertPreferences.hourKey) private var hour = 10
    @AppStorage(AlertPreferences.minuteKey) private var minute = 0
    @AppStorage(AlertPreferences.strictnessKey) private var strictness = AlertStrictness.strong
    @State private var status: String?

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date() },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                hour = parts.hour ?? 10
                minute = parts.minute ?? 0
            }
        )
    }

    /// Enabled sources, grouped by folder as in Sources, folders first and then those in none.
    private var groups: [(folder: String?, sources: [Source])] {
        let enabledSources = model.sources.filter(\.enabled)
        let folders = Set(enabledSources.compactMap(\.folder)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var result: [(folder: String?, sources: [Source])] = folders.map { folder in
            (folder, enabledSources.filter { $0.folder == folder })
        }
        let loose = enabledSources.filter { $0.folder == nil }
        if !loose.isEmpty { result.append((nil, loose)) }
        return result
    }

    private var chosenCount: Int {
        model.sources.filter { $0.enabled && $0.alertsEnabled }.count
    }

    var body: some View {
        Form {
            Section {
                Toggle("Send a daily alert for very trending stories", isOn: $enabled)
                    .onChange(of: enabled) { _, isOn in
                        guard isOn else { return }
                        Task {
                            if !(await model.alertNotifier.requestPermission()) {
                                status = "macOS is not allowing CraftPeep's notifications. Turn them on in System Settings → Notifications."
                            }
                        }
                    }
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                    .disabled(!enabled)
                Picker("A story must have", selection: $strictness) {
                    ForEach(AlertStrictness.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .disabled(!enabled)
                Text("""
                    One notification a day with up to three stories first seen in the last 24 hours, from the \
                    sources ticked below, and covered by at least \(strictness.minimumPublications) publications \
                    or with \(strictness.minimumPoints) or more points on Hacker News. No notification when \
                    nothing qualifies, and no story twice. CraftPeep must be running, which it is from login \
                    when Open at Login is on; if the Mac is asleep at the time, the alert comes when it wakes.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button(model.isRunningAlert ? "Checking…" : "Send Test Alert") {
                        Task { status = await model.runTrendingAlert(test: true) }
                    }
                    .disabled(model.isRunningAlert)
                    if status?.contains("System Settings") == true {
                        Button("Open Notification Settings") { AlertNotifier.openNotificationSettings() }
                    }
                    Spacer()
                    if let last = AlertPreferences.lastRun {
                        Text("Last ran \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let status {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                if groups.isEmpty {
                    Text("No sources are switched on.").foregroundStyle(.secondary)
                }
                ForEach(groups, id: \.folder) { group in
                    if let folder = group.folder {
                        Toggle(isOn: folderBinding(folder, sources: group.sources)) {
                            Label(folder, systemImage: "folder").fontWeight(.semibold)
                        }
                    } else {
                        Text("Not in a folder").fontWeight(.semibold).foregroundStyle(.secondary)
                    }
                    ForEach(group.sources) { source in
                        Toggle(source.name, isOn: Binding(
                            get: { source.alertsEnabled },
                            set: { on in Task { await model.setAlertsEnabled(on, source: source) } }
                        ))
                        .padding(.leading, group.folder == nil ? 0 : 20)
                    }
                }
            } header: {
                Text("Sources that can trigger the alert (\(chosenCount) chosen)")
            } footer: {
                Text("Coverage is counted across every source, so a story from a ticked source counts when many publications pick it up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// On when every source in the folder is ticked; switching it ticks or clears them all.
    private func folderBinding(_ folder: String, sources: [Source]) -> Binding<Bool> {
        Binding(
            get: { !sources.isEmpty && sources.allSatisfy(\.alertsEnabled) },
            set: { on in Task { await model.setAlertsEnabled(on, folder: folder) } }
        )
    }
}
