import AppKit
import Foundation
import Observation

enum GitHubSignInState {
    case idle
    case awaitingUser(GitHubAuth.DeviceCode)
    case error(String)
}

@Observable @MainActor
final class ItemStore {
    var items: [Item] = []
    var isLoading = false
    var errorMessage: String?
    var signInState: GitHubSignInState = .idle
    private(set) var githubToken: String
    let isOAuthConfigured: Bool

    private let github = GitHubProvider()
    private let auth = GitHubAuth()
    private var pollTask: Task<Void, Never>?
    private var signInTask: Task<Void, Never>?

    init() {
        self.githubToken = KeychainStore.get(GitHubProvider.tokenKey) ?? ""
        self.isOAuthConfigured = (Bundle.main.object(forInfoDictionaryKey: "GitHubOAuthClientID") as? String).map { !$0.isEmpty } ?? false
    }

    func saveGitHubToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(GitHubProvider.tokenKey)
        } else {
            KeychainStore.set(trimmed, for: GitHubProvider.tokenKey)
        }
        githubToken = trimmed
        restartPolling()
    }

    /// Idempotent — safe to call from a SwiftUI `.task`/`.onAppear` on launch.
    func startPolling() {
        guard pollTask == nil, !githubToken.isEmpty else { return }
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// User-triggered refresh — runs out-of-band from the poll loop.
    func refresh() async {
        await runFetch(silent: false)
    }

    func markRead(_ item: Item) async {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard !items[idx].isRead else { return }
        items[idx].isRead = true
        do {
            try await github.markRead(item)
        } catch {
            if let i = items.firstIndex(where: { $0.id == item.id }) {
                items[i].isRead = false
            }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func beginGitHubSignIn() {
        cancelGitHubSignIn()
        signInState = .idle
        signInTask = Task { [weak self] in
            guard let self else { return }
            do {
                let code = try await self.auth.requestDeviceCode()
                self.signInState = .awaitingUser(code)
                NSWorkspace.shared.open(code.verificationURI)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(code.userCode, forType: .string)

                let token = try await self.auth.pollForToken(code)
                self.saveGitHubToken(token)
                self.signInState = .idle
            } catch is CancellationError {
                self.signInState = .idle
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.signInState = .error(msg)
            }
        }
    }

    func cancelGitHubSignIn() {
        signInTask?.cancel()
        signInTask = nil
    }

    private func restartPolling() {
        stopPolling()
        startPolling()
    }

    private func pollLoop() async {
        // First iteration shows a spinner — the user just launched or saved a token.
        // Subsequent iterations are silent so the UI doesn't flicker every minute.
        var firstIteration = true
        while !Task.isCancelled {
            let nextDelay = await runFetch(silent: !firstIteration)
            firstIteration = false
            do { try await Task.sleep(for: .seconds(nextDelay)) }
            catch { return }
        }
    }

    @discardableResult
    private func runFetch(silent: Bool) async -> TimeInterval {
        if !silent { isLoading = true }
        defer { if !silent { isLoading = false } }
        do {
            let result = try await github.fetch()
            if let newItems = result.items {
                let doneIds = Set(items.filter { $0.isRead }.map(\.id))
                let kept = items.filter { doneIds.contains($0.id) }
                let fresh = newItems.filter { !doneIds.contains($0.id) }
                items = (kept + fresh).sorted { $0.updatedAt > $1.updatedAt }
                Task { await NotificationService.shared.notify(items: items) }
            }
            if !silent { errorMessage = nil }
            return result.nextPollAfter
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if silent {
                #if DEBUG
                print("[Inbox] background poll error: \(msg)")
                #endif
            } else {
                errorMessage = msg
            }
            return 60
        }
    }
}
