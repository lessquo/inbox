import SwiftUI

struct SettingsView: View {
    @Environment(ItemStore.self) private var store
    @State private var draft: String = ""
    @State private var justSaved = false

    var body: some View {
        Form {
            Section("GitHub") {
                SecureField("Personal Access Token", text: $draft)
                Text("Create a **classic** token with the `notifications` scope at [github.com/settings/tokens](https://github.com/settings/tokens). The Notifications API does not yet support fine-grained tokens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Save") {
                        store.saveGitHubToken(draft)
                        justSaved = true
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft == store.githubToken)

                    Button("Clear", role: .destructive) {
                        draft = ""
                        store.saveGitHubToken("")
                    }
                    .disabled(store.githubToken.isEmpty && draft.isEmpty)

                    Spacer()

                    if !store.githubToken.isEmpty {
                        Label(justSaved ? "Saved" : "Token set", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 240)
        .onAppear { draft = store.githubToken }
        .onChange(of: store.githubToken) { _, new in
            draft = new
            justSaved = false
        }
    }
}
