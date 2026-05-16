import Foundation

struct FetchResult: Sendable {
    /// `nil` means the server reported no change since the previous fetch (e.g. HTTP 304).
    let items: [Item]?
    /// Seconds the caller should wait before polling again. Providers should surface
    /// any server-recommended cadence here (GitHub returns it as `X-Poll-Interval`).
    let nextPollAfter: TimeInterval
}

protocol ItemProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var isConfigured: Bool { get }

    func fetch() async throws -> FetchResult
    func markRead(_ item: Item) async throws
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
