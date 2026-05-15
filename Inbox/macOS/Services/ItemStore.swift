import Foundation
import Observation

@Observable @MainActor
final class ItemStore {
    var items: [Item] = []
    var isLoading = false
    var errorMessage: String?
    private(set) var githubToken: String

    private let github = GitHubProvider()

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
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched = try await github.fetch()
            items = fetched.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func markDone(_ item: Item) async {
        // Optimistic: remove immediately, restore on error.
        let snapshot = items
        items.removeAll { $0.id == item.id }
        do {
            try await github.markDone(item)
        } catch {
            items = snapshot
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
