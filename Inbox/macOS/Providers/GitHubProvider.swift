import Foundation

/// GitHub notifications provider. Reads its token from the Keychain on each call,
/// so the credential never needs to be passed around at the API surface.
struct GitHubProvider: InboxProvider {
    static let tokenKey = "github_token"

    let id = "github"
    let displayName = "GitHub"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    var isConfigured: Bool {
        (KeychainStore.get(Self.tokenKey) ?? "").isEmpty == false
    }

    func fetch() async throws -> [Item] {
        let token = try requireToken()
        var req = URLRequest(url: URL(string: "https://api.github.com/notifications?all=false")!)
        applyHeaders(&req, token: token)

        let (data, response) = try await session.data(for: req)
        try Self.checkStatus(response, data: data)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let notifications = try decoder.decode([GHNotification].self, from: data)

        return notifications.map { n in
            Item(
                id: "github:\(n.id)",
                sourceId: id,
                extId: n.id,
                title: n.subject.title,
                subtitle: n.repository.fullName,
                reason: n.reason,
                updatedAt: n.updatedAt,
                url: Self.htmlURL(for: n),
                isRead: !n.unread
            )
        }
    }

    func markDone(_ item: Item) async throws {
        let token = try requireToken()
        var req = URLRequest(url: URL(string: "https://api.github.com/notifications/threads/\(item.extId)")!)
        req.httpMethod = "PATCH"
        applyHeaders(&req, token: token)

        let (data, response) = try await session.data(for: req)
        try Self.checkStatus(response, data: data)
    }

    private func requireToken() throws -> String {
        let token = (KeychainStore.get(Self.tokenKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw ProviderError.notAuthenticated }
        return token
    }

    private func applyHeaders(_ req: inout URLRequest, token: String) {
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    }

    private static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ProviderError.httpError(status: http.statusCode, body: body)
        }
    }

    // GitHub's notification subject.url is an *API* URL. Map common shapes to
    // their web counterparts; otherwise fall back to the repo page.
    private static func htmlURL(for n: GHNotification) -> URL? {
        if let api = n.subject.url, let url = transformAPIURL(api) { return url }
        return URL(string: n.repository.htmlUrl)
    }

    private static func transformAPIURL(_ api: String) -> URL? {
        guard let url = URL(string: api) else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 5, parts[0] == "repos" else { return nil }
        let owner = parts[1], repo = parts[2], kind = parts[3], rest = parts[4...].joined(separator: "/")
        let suffix: String
        switch kind {
        case "issues":   suffix = "issues/\(rest)"
        case "pulls":    suffix = "pull/\(rest)"
        case "commits":  suffix = "commit/\(rest)"
        case "releases": suffix = "releases/tag/\(rest)"   // best-effort
        default: return nil
        }
        return URL(string: "https://github.com/\(owner)/\(repo)/\(suffix)")
    }
}

private struct GHNotification: Decodable {
    let id: String
    let unread: Bool
    let reason: String
    let updatedAt: Date
    let subject: Subject
    let repository: Repository

    struct Subject: Decodable {
        let title: String
        let url: String?
        let latestCommentUrl: String?
        let type: String
    }
    struct Repository: Decodable {
        let fullName: String
        let htmlUrl: String
    }
}
