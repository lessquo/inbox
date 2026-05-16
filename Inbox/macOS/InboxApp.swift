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

        MenuBarExtra {
            MenuBarView()
                .environment(store)
        } label: {
            Image(systemName: store.items.contains(where: { !$0.isRead }) ? "tray.full" : "tray")
        }
        .menuBarExtraStyle(.window)
    }
}
