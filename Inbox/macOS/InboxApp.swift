import SwiftUI

@main
struct InboxApp: App {
    @State private var store = ItemStore()

    var body: some Scene {
        WindowGroup("Inbox") {
            ContentView()
                .environment(store)
                .frame(minWidth: 560, minHeight: 380)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}
