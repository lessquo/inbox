import Foundation

protocol InboxProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var isConfigured: Bool { get }

    func fetch() async throws -> [Item]
    func markDone(_ item: Item) async throws
}

enum ProviderError: LocalizedError {
    case notAuthenticated
    case httpError(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Add a token in Settings (⌘,)."
        case .httpError(let status, let body):
            let trimmed = body.prefix(200)
            return "HTTP \(status): \(trimmed)"
        }
    }
}
