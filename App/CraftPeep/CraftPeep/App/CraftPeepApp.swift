import Domain
import SwiftUI

@main
struct CraftPeepApp: App {
    @State private var model = AppModel()
    @AppStorage("showMenuBarItem") private var showMenuBarItem = true
    @AppStorage(UnreadBadgeStyle.storageKey) private var badgeStyle = UnreadBadgeStyle.number

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
                ForEach(Array(SidebarSection.main.enumerated()), id: \.element) { index, section in
                    Button(section.title) { model.section = section }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                }
            }
            CommandMenu("Story") {
                // Command-Return, not plain Return: a menu shortcut without a modifier would also fire while
                // typing in the search field. Plain Return is handled by the story list itself.
                Button("Open Original") { model.openSelected() }
                    .keyboardShortcut(.return, modifiers: .command)
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
                Button("Mark All as Read") { Task { await model.markAllRead() } }
                    .keyboardShortcut("k")
                    .disabled(!model.hasUnreadInList || model.section == .radar)
            }
            // Story commands act on the selection; without one there is nothing to act on.
        }

        MenuBarExtra(isInserted: $showMenuBarItem) {
            PulseView(model: model)
        } label: {
            let count = model.unreadTopCount
            switch badgeStyle {
            case .number:
                // The count is part of the label so VoiceOver reads it.
                Label(count > 0 ? "\(count)" : "", systemImage: count > 0 ? "newspaper.fill" : "newspaper")
                    .labelStyle(.titleAndIcon)
                    .accessibilityLabel("CraftPeep, \(count) unread top stories")
            case .dot:
                Label(count > 0 ? "•" : "", systemImage: count > 0 ? "newspaper.fill" : "newspaper")
                    .labelStyle(.titleAndIcon)
                    .accessibilityLabel(count > 0 ? "CraftPeep, unread top stories" : "CraftPeep, all caught up")
            case .hidden:
                Image(systemName: "newspaper")
                    .accessibilityLabel("CraftPeep")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
