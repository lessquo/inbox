import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(ItemStore.self) private var store

    var body: some View {
        Form {
            Section("GitHub") {
                if !store.isOAuthConfigured {
                    Text("GitHub OAuth client ID is not configured. Register an OAuth App and set `GITHUB_OAUTH_CLIENT_ID` in `Local.xcconfig`.")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    content
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 280)
    }

    @ViewBuilder
    private var content: some View {
        switch store.signInState {
        case .idle:
            if store.githubToken.isEmpty {
                Button("Connect with GitHub") { store.beginGitHubSignIn() }
                    .keyboardShortcut(.defaultAction)
                Text("Opens GitHub in your browser to authorize Inbox to read notifications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Label("Connected", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Disconnect", role: .destructive) {
                        store.saveGitHubToken("")
                    }
                }
            }

        case .awaitingUser(let code):
            VStack(alignment: .leading, spacing: 8) {
                Text("Enter this code on GitHub:")
                Text(code.userCode)
                    .font(.system(.title, design: .monospaced))
                    .textSelection(.enabled)
                Text("Your browser was opened to \(code.verificationURI.absoluteString). The code is also on your clipboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Open Browser Again") {
                        NSWorkspace.shared.open(code.verificationURI)
                    }
                    Button("Cancel", role: .cancel) {
                        store.cancelGitHubSignIn()
                    }
                }
            }

        case .error(let msg):
            VStack(alignment: .leading, spacing: 8) {
                Text(msg).foregroundStyle(.red)
                Button("Try Again") { store.beginGitHubSignIn() }
            }
        }
    }
}
