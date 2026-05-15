import SwiftUI

struct ContentView: View {
    @Environment(ItemStore.self) private var store

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Inbox")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await store.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(store.isLoading || store.githubToken.isEmpty)
                        .help("Refresh")
                    }
                }
                .overlay(alignment: .bottom) {
                    if let msg = store.errorMessage {
                        Text(msg)
                            .font(.caption)
                            .padding(8)
                            .background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                            .padding()
                            .transition(.opacity)
                    }
                }
        }
        .task {
            if !store.githubToken.isEmpty { await store.refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.githubToken.isEmpty {
            ContentUnavailableView(
                "Add a GitHub token",
                systemImage: "key",
                description: Text("Open Settings (⌘,) and paste a personal access token with the `notifications` scope.")
            )
        } else if store.items.isEmpty {
            ContentUnavailableView(
                store.isLoading ? "Loading…" : "Inbox zero",
                systemImage: store.isLoading ? "hourglass" : "tray",
                description: Text(store.isLoading ? "" : "Nothing to read.")
            )
        } else {
            List(store.items) { item in
                ItemRow(item: item)
            }
            .listStyle(.inset)
        }
    }
}
