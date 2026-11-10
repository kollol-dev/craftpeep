import SwiftUI

@main
struct CraftPeepApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 560, minHeight: 420)
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r")
                .disabled(model.isRefreshing || model.startupError != nil)
            }
        }
    }
}
