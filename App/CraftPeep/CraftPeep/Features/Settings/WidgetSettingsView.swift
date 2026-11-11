import SwiftUI
import WidgetSpec

struct WidgetSettingsView: View {
    let model: AppModel

    @AppStorage(WidgetPreferences.enabledKey) private var enabled = false
    @AppStorage(WidgetPreferences.sizeKey) private var size = WidgetSize.medium.rawValue
    @AppStorage(WidgetPreferences.subjectKey) private var subject = "all"
    @AppStorage(WidgetPreferences.showSourcesKey) private var showSources = true

    var body: some View {
        Form {
            Section {
                Toggle("Show the News List on the desktop", isOn: $enabled)
                Text("It sits on the desktop, behind your windows, on every Space. Drag it by its edge or title to move it; it stays where you leave it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("News List") {
                Picker("Size", selection: $size) {
                    Text("Small (3 stories)").tag(WidgetSize.small.rawValue)
                    Text("Medium (6 stories)").tag(WidgetSize.medium.rawValue)
                    Text("Large (10 stories)").tag(WidgetSize.large.rawValue)
                }
                Picker("Subject", selection: $subject) {
                    Text("Everything").tag("all")
                    Text("AI").tag("ai")
                }
                Toggle("Show source and age", isOn: $showSources)
            }
            Section {
                Text("The widget reads the stories CraftPeep has already stored. It makes no network requests of its own and uses no AI.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: [enabled.description, size, subject, showSources.description]) {
            Task { await model.refreshWidget() }
        }
    }
}
