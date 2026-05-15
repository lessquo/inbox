import Foundation

/// GitHub notifications provider. Reads its token from the Keychain on each call,
/// so the credential never needs to be passed around at the API surface.
struct GitHubProvider: ItemProvider {
    static let tokenKey = "github_token"

    let id = "github"
    let displayName = "GitHub"

    private let session: URLSession
    private let conditional = ConditionalState()

    init(session: URLSession = .shared) {
        self.session = session
    }

    var isConfigured: Bool {
        (KeychainStore.get(Self.tokenKey) ?? "").isEmpty == false
    }

    func fetch() async throws -> FetchResult {
        let token = try requireToken()
        var req = URLRequest(url: URL(string: "https://api.github.com/notifications?all=false")!)
        // We track Last-Modified ourselves; bypass URLSession's cache so a server 304
        // surfaces as 304 instead of being silently replayed as a 200 from cache.
        req.cachePolicy = .reloadIgnoringLocalCacheData
        applyHeaders(&req, token: token)
        if let lm = await conditional.lastModified {
            req.setValue(lm, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.httpError(status: -1, body: "")
        }

        let nextPoll = Self.parsePollInterval(http)
        if http.statusCode == 304 {
            return FetchResult(items: nil, nextPollAfter: nextPoll)
        }
        try Self.checkStatus(http, data: data)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let notifications = try decoder.decode([GHNotification].self, from: data)

        if let lm = http.value(forHTTPHeaderField: "Last-Modified") {
            await conditional.set(lm)
        }

        let items = notifications.map { n in
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
        return FetchResult(items: items, nextPollAfter: nextPoll)
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

    private static func parsePollInterval(_ http: HTTPURLResponse) -> TimeInterval {
        if let raw = http.value(forHTTPHeaderField: "X-Poll-Interval"),
           let seconds = TimeInterval(raw), seconds > 0 {
            return seconds
        }
        return 60
    }

    private static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ProviderError.httpError(status: http.statusCode, body: body)
        }
    }

    // GitHub's notification subject.url is an *API* URL. Map common shapes to
    // their web counterparts; otherwise fall back to the repo page. When the
    // notification has a latest_comment_url, append the matching fragment so
    // the link lands on the specific comment — matching github.com's redirect
    // from the notifications page.
    private static func htmlURL(for n: GHNotification) -> URL? {
        guard let api = n.subject.url, let base = transformAPIURL(api) else {
            return URL(string: n.repository.htmlUrl)
        }
        if let commentAPI = n.subject.latestCommentUrl,
           let fragment = commentFragment(commentAPI) {
            return URL(string: base.absoluteString + "#" + fragment)
        }
        return base
    }

    private static func commentFragment(_ api: String) -> String? {
        guard let url = URL(string: api) else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 5, parts[0] == "repos", let id = parts.last else { return nil }
        switch parts[3] {
        case "issues" where parts.count >= 6 && parts[4] == "comments":
            return "issuecomment-\(id)"
        case "pulls" where parts.count >= 6 && parts[4] == "comments":
            return "discussion_r\(id)"
        case "comments":
            return "commitcomment-\(id)"
        default:
            return nil
        }
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

private actor ConditionalState {
    var lastModified: String?
    func set(_ value: String) { lastModified = value }
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
