import SwiftUI

struct MenuBarView: View {
    @Environment(ItemStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 380, height: 480)
    }

    private var header: some View {
        HStack {
            Text("Inbox").font(.headline)
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(store.isLoading || store.githubToken.isEmpty)
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if store.githubToken.isEmpty {
            ContentUnavailableView(
                "Add a token",
                systemImage: "key",
                description: Text("Open Settings to authenticate.")
            )
        } else if store.items.isEmpty {
            ContentUnavailableView(
                store.isLoading ? "Loading…" : "Inbox zero",
                systemImage: store.isLoading ? "hourglass" : "tray",
                description: Text(store.isLoading ? "" : "Nothing to read.")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.items) { item in
                        ItemRow(item: item)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Settings…") { openSettings() }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
