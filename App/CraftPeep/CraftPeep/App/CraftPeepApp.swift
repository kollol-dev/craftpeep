import Domain
import SwiftUI

@main
struct CraftPeepApp: App {
    @State private var model = AppModel()
    @AppStorage("showMenuBarItem") private var showMenuBarItem = true

    var body: some Scene {
        Window("CraftPeep", id: "main") {
            MainView(model: model)
                .frame(minWidth: 900, minHeight: 520)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh") { Task { await model.refresh() } }
                    .keyboardShortcut("r")
                    .disabled(model.isRefreshing || model.startupError != nil)
                Divider()
                ForEach(Array(SidebarSection.allCases.enumerated()), id: \.element) { index, section in
                    Button(section.title) { model.section = section }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                }
            }
            CommandMenu("Story") {
                Button("Open Original") { model.openSelected() }
                    .keyboardShortcut(.return)
                Button("Open Discussion") { model.openSelectedDiscussion() }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .disabled(model.selectedItem?.summary.discussionURL == nil)
                Divider()
                Button(model.selectedItem?.summary.isSaved == true ? "Remove from Read Later" : "Read Later") {
                    Task { await model.toggleSaved() }
                }
                .keyboardShortcut("d")
                Button(model.selectedItem?.summary.isFavourite == true ? "Remove Favourite" : "Favourite") {
                    Task { await model.toggleFavourite() }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Mark as Unread") { Task { await model.markSelectedUnread() } }
                    .keyboardShortcut("u")
            }
            // Story commands act on the selection; without one there is nothing to act on.
        }

        MenuBarExtra(isInserted: $showMenuBarItem) {
            PulseView(model: model)
        } label: {
            // The count is part of the label so VoiceOver reads it.
            Label(
                model.unreadTopCount > 0 ? "\(model.unreadTopCount)" : "",
                systemImage: model.unreadTopCount > 0 ? "newspaper.fill" : "newspaper"
            )
            .labelStyle(.titleAndIcon)
            .accessibilityLabel("CraftPeep, \(model.unreadTopCount) unread top stories")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
