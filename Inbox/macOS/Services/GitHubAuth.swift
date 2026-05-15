import Foundation

/// GitHub OAuth Device Flow client. No client secret needed — the app shows the
/// user a short code, opens github.com/login/device, and polls until the user
/// authorizes (or denies / lets the code expire).
actor GitHubAuth {
    struct DeviceCode: Sendable {
        let userCode: String
        let verificationURI: URL
        let deviceCode: String
        let interval: TimeInterval
        let expiresAt: Date
    }

    enum AuthError: LocalizedError {
        case missingClientID
        case denied
        case expired
        case unexpected(String)

        var errorDescription: String? {
            switch self {
            case .missingClientID: "GitHub OAuth client ID not configured. Set GITHUB_OAUTH_CLIENT_ID in Local.xcconfig."
            case .denied:          "Authorization was denied."
            case .expired:         "The device code expired. Try again."
            case .unexpected(let m): m
            }
        }
    }

    private let session: URLSession
    private let clientID: String?
    private let scope = "notifications"

    init(session: URLSession = .shared) {
        self.session = session
        let id = Bundle.main.object(forInfoDictionaryKey: "GitHubOAuthClientID") as? String
        self.clientID = (id?.isEmpty == false) ? id : nil
    }

    var isConfigured: Bool { clientID != nil }

    func requestDeviceCode() async throws -> DeviceCode {
        guard let id = clientID else { throw AuthError.missingClientID }
        let body = form(["client_id": id, "scope": scope])
        let data = try await postForm(URL(string: "https://github.com/login/device/code")!, body: body)

        struct DC: Decodable {
            let device_code: String
            let user_code: String
            let verification_uri: String
            let expires_in: Double
            let interval: Double
        }
        let dc = try JSONDecoder().decode(DC.self, from: data)
        guard let url = URL(string: dc.verification_uri) else {
            throw AuthError.unexpected("Bad verification_uri")
        }
        return DeviceCode(
            userCode: dc.user_code,
            verificationURI: url,
            deviceCode: dc.device_code,
            interval: dc.interval,
            expiresAt: Date().addingTimeInterval(dc.expires_in)
        )
    }

    /// Polls until the user authorizes, denies, or the code expires. Honors
    /// Task cancellation so the Settings UI can cancel mid-flow.
    func pollForToken(_ code: DeviceCode) async throws -> String {
        guard let id = clientID else { throw AuthError.missingClientID }
        var interval = code.interval
        while Date() < code.expiresAt {
            try await Task.sleep(for: .seconds(interval))
            try Task.checkCancellation()

            let body = form([
                "client_id": id,
                "device_code": code.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            let data = try await postForm(URL(string: "https://github.com/login/oauth/access_token")!, body: body)

            struct Resp: Decodable {
                let access_token: String?
                let error: String?
            }
            let r = try JSONDecoder().decode(Resp.self, from: data)
            if let token = r.access_token { return token }
            switch r.error {
            case "authorization_pending": continue
            case "slow_down":              interval += 5
            case "access_denied":          throw AuthError.denied
            case "expired_token":          throw AuthError.expired
            default:                       throw AuthError.unexpected(r.error ?? "unknown response")
            }
        }
        throw AuthError.expired
    }

    private func postForm(_ url: URL, body: Data) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AuthError.unexpected("HTTP \(http.statusCode): \(body)")
        }
        return data
    }

    private func form(_ pairs: [String: String]) -> Data {
        var cs = CharacterSet.urlQueryAllowed
        cs.remove(charactersIn: "+&=")
        let encoded = pairs
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: cs) ?? "")" }
            .joined(separator: "&")
        return Data(encoded.utf8)
    }
}
