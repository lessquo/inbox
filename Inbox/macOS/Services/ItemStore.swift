import Foundation
import Observation

@Observable @MainActor
final class ItemStore {
    var items: [Item] = []
    var isLoading = false
    var errorMessage: String?
    private(set) var githubToken: String

    private let github = GitHubProvider()
    private var pollTask: Task<Void, Never>?

    init() {
        self.githubToken = KeychainStore.get(GitHubProvider.tokenKey) ?? ""
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

    func markDone(_ item: Item) async {
        let snapshot = items
        items.removeAll { $0.id == item.id }
        do {
            try await github.markDone(item)
        } catch {
            items = snapshot
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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
                items = newItems.sorted { $0.updatedAt > $1.updatedAt }
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
