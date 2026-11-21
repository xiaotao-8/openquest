import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

/// IM login (OAuth 2.0 authorization code) for Feishu / DingTalk / Slack.
///
/// No credential is ever typed into this app. The App holds no client id
/// and no client secret: both live on the companion service
/// (`lingyu-im-oauth`, a small process on the paired computer, port 18790),
/// which builds the authorize URL, exchanges the code, and fetches the
/// profile. The App only ever sees the short-lived code (direct-scheme
/// mode) or a state ticket (companion-callback mode), plus the tokens the
/// companion hands back — those go straight into the keychain, never into
/// a file, and are never shown.
///
/// Redirect modes (per provider, configured on the companion):
/// - direct-scheme: the provider redirects to `cn.lingyu://oauth/<provider>`
///   (this app's own scheme, already registered in Info.plist) and the App
///   exchanges the code with POST /im/oauth/exchange. Used only when the
///   provider's console accepts the custom scheme as a redirect URI.
/// - companion-callback: the provider redirects to the companion's
///   `http://<host>:18790/oauth/callback`; the companion exchanges the code
///   at once, keeps the result under the state for five minutes, and sends
///   the browser on to `cn.lingyu://oauth/<provider>?state=...`; the App
///   then fetches the result with POST /im/oauth/result. The state must
///   have been pre-registered by a signed /start call, or the companion
///   refuses the callback (login-CSRF protection).
/// Slack requires an HTTPS redirect URL, so Slack can only log in once the
/// companion has an HTTPS front (a tunnel or a certificate); until then its
/// row honestly says so. Feishu and DingTalk take the companion's http
/// callback, but whether their consoles accept a public-IP http URL is
/// unverified until the app is registered — see NOTES.md.
@MainActor
final class IMAuthStore: ObservableObject {
    /// The platform with a login sheet open right now (spinner on its row).
    @Published private(set) var activePlatform: String?

    /// Per-provider setup, from GET /im/oauth/status. Nil until fetched.
    @Published private(set) var providerStatus: [String: IMProviderStatus] = [:]

    private var activeSession: ASWebAuthenticationSession?
    private var pending: PendingLogin?
    private let presentationContext = PresentationContext()

    private struct PendingLogin {
        var platform: String
        var state: String
        var continuation: CheckedContinuation<URL, any Error>
    }

    /// The deep-link fallback: `cn.lingyu://oauth/<platform>?code=...` (or
    /// `?state=...`). The ASWebAuthenticationSession completion handler is
    /// the normal path; this only fires if the session was torn down and the
    /// system delivered the URL through the app instead. Returns false when
    /// there is no pending login for the URL, so the caller can ignore it.
    func handleCallback(_ url: URL) -> Bool {
        guard let pending,
              url.host == "oauth",
              url.pathComponents.dropFirst().first == pending.platform,
              url.queryValue("state") == pending.state else { return false }
        self.pending = nil
        pending.continuation.resume(returning: url)
        return true
    }

    /// Run the whole login for one platform: fetch the authorize URL from
    /// the companion, open the provider's own login page, exchange the
    /// result for tokens + profile. Throws IMAuthError; a cancelled sheet
    /// throws .cancelled and the caller stays silent about it.
    func startLogin(platform: String, computer: Computer) async throws -> IMLoginResult {
        let state = Self.randomState()
        let start = try await requestStart(platform: platform, state: state, computer: computer)
        guard start.configured else {
            throw IMAuthError.providerNotConfigured(platform: platform, detail: start.detail)
        }
        guard let authorizeURL = URL(string: start.authorizeURL) else {
            throw IMAuthError.invalidAuthorizeURL
        }
        activePlatform = platform
        defer { activePlatform = nil; activeSession = nil }
        let callbackURL = try await runAuthSession(url: authorizeURL, platform: platform, state: state)
        let query = callbackURL.queryDictionary
        guard query["state"] == state else { throw IMAuthError.stateMismatch }
        if let refused = query["error"] { throw IMAuthError.providerRefused(refused) }
        if let code = query["code"] {
            return try await requestExchange(platform: platform, code: code, redirectURI: start.redirectURI, computer: computer)
        }
        return try await requestResult(platform: platform, state: state, computer: computer)
    }

    /// Refresh the setup table from the companion. Failures leave the old
    /// table alone; the login attempt itself reports the real error.
    func refreshStatus(computer: Computer?) async {
        guard let computer, let base = Self.companionBaseURL(computer: computer) else { return }
        do {
            let request = try signedRequest(url: base.appendingPathComponent("im/oauth/status"), method: "GET", body: nil, computer: computer)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let decoded = try decoder.decode(StatusResponse.self, from: data)
            providerStatus = decoded.providers
        } catch {
            return
        }
    }

    // MARK: - Auth session

    private func runAuthSession(url: URL, platform: String, state: String) async throws -> URL {
        // The continuation body runs synchronously on this actor, so a
        // strong self capture here is safe; the session's own completion
        // handler (which fires later, on any thread) is the one that must
        // hop back to the main actor and capture weakly.
        try await withCheckedThrowingContinuation { continuation in
            self.pending = PendingLogin(platform: platform, state: state, continuation: continuation)
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "cn.lingyu") { [weak self] callbackURL, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard let pending = self.pending else { return }
                    self.pending = nil
                    if let callbackURL {
                        pending.continuation.resume(returning: callbackURL)
                    } else if let error {
                        pending.continuation.resume(throwing: error)
                    } else {
                        pending.continuation.resume(throwing: IMAuthError.invalidCallback)
                    }
                }
            }
            session.presentationContextProvider = self.presentationContext
            session.prefersEphemeralWebBrowserSession = false
            self.activeSession = session
            if !session.start() {
                self.pending = nil
                continuation.resume(throwing: IMAuthError.invalidCallback)
            }
        }
    }

    // MARK: - Companion client

    /// The companion lives on the paired computer: same host as the first
    /// pairing URL, port 18790, plain http. The first pairing URL is the
    /// public one by the pairing convention, so this is the address the
    /// phone already reaches the computer at.
    static func companionBaseURL(computer: Computer) -> URL? {
        guard let raw = computer.urls.first,
              let components = URLComponents(string: raw),
              let host = components.host else { return nil }
        var parts = URLComponents()
        parts.scheme = "http"
        parts.host = host
        parts.port = 18790
        return parts.url
    }

    private func requestStart(platform: String, state: String, computer: Computer) async throws -> StartResponse {
        guard let base = Self.companionBaseURL(computer: computer) else { throw IMAuthError.notPaired }
        var parts = URLComponents(url: base.appendingPathComponent("im/oauth/start"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [
            URLQueryItem(name: "provider", value: platform),
            URLQueryItem(name: "state", value: state)
        ]
        guard let url = parts?.url else { throw IMAuthError.notPaired }
        let request = try signedRequest(url: url, method: "GET", body: nil, computer: computer)
        return try await send(request, as: StartResponse.self)
    }

    private func requestExchange(platform: String, code: String, redirectURI: String, computer: Computer) async throws -> IMLoginResult {
        guard let base = Self.companionBaseURL(computer: computer) else { throw IMAuthError.notPaired }
        let body = try JSONEncoder().encode(ExchangeRequest(provider: platform, code: code, redirectURI: redirectURI))
        let request = try signedRequest(url: base.appendingPathComponent("im/oauth/exchange"), method: "POST", body: body, computer: computer)
        return try await send(request, as: IMLoginResult.self)
    }

    private func requestResult(platform: String, state: String, computer: Computer) async throws -> IMLoginResult {
        guard let base = Self.companionBaseURL(computer: computer) else { throw IMAuthError.notPaired }
        let body = try JSONEncoder().encode(ResultRequest(provider: platform, state: state))
        let request = try signedRequest(url: base.appendingPathComponent("im/oauth/result"), method: "POST", body: body, computer: computer)
        return try await send(request, as: IMLoginResult.self)
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw IMAuthError.companionUnreachable
        }
        guard let http = response as? HTTPURLResponse else { throw IMAuthError.companionUnreachable }
        switch http.statusCode {
        case 200:
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                return try decoder.decode(T.self, from: data)
            } catch {
                throw IMAuthError.exchangeFailed(L("登录失败，请重试。"))
            }
        case 401:
            // The companion is reachable but does not recognize this phone:
            // the box key changed (re-paired) and the companion config was
            // never updated. Not a network failure, so it gets its own line.
            throw IMAuthError.notRegistered
        case 404:
            throw IMAuthError.resultNotReady
        case 501:
            throw IMAuthError.providerNotConfigured(platform: nil, detail: "https-required")
        default:
            let detail = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
            throw IMAuthError.exchangeFailed(detail ?? L("登录失败，请重试。"))
        }
    }

    /// HMAC-SHA256 over `timestamp\nmethod\npath\nsha256hex(body)`, keyed
    /// by the pairing box key. The companion holds one box key per paired
    /// phone (filled in at deploy time) and picks it by the
    /// X-LinGyU-Device header, so only the paired phone can call it. The
    /// box key never leaves the phone and the companion; the client secret
    /// never leaves the companion.
    private func signedRequest(url: URL, method: String, body: Data?, computer: Computer) throws -> URLRequest {
        guard let boxKey = computer.boxKeyData, !boxKey.isEmpty else { throw IMAuthError.noBoxKey }
        let identity = try DeviceIdentity.loadOrCreate()
        let timestamp = Int(Date().timeIntervalSince1970)
        let bodyHash = SHA256.hash(data: body ?? Data()).map { String(format: "%02x", $0) }.joined()
        let stringToSign = "\(timestamp)\n\(method)\n\(url.path)\n\(bodyHash)"
        let mac = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: SymmetricKey(data: boxKey))
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(identity.deviceKeyBase64URL, forHTTPHeaderField: "X-LinGyU-Device")
        request.setValue(Base64URL.encode(Data(mac)), forHTTPHeaderField: "X-LinGyU-Signature")
        request.setValue(String(timestamp), forHTTPHeaderField: "X-LinGyU-Timestamp")
        return request
    }

    private static func randomState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Base64URL.encode(bytes)
    }

    // MARK: - Wire models

    private struct StartResponse: Decodable {
        var authorizeURL: String
        var redirectURI: String
        var redirectMode: String
        var configured: Bool
        var detail: String?

        enum CodingKeys: String, CodingKey {
            case authorizeURL = "authorize_url"
            case redirectURI = "redirect_uri"
            case redirectMode = "redirect_mode"
            case configured, detail
        }
    }

    private struct ExchangeRequest: Encodable {
        var provider: String
        var code: String
        var redirectURI: String

        enum CodingKeys: String, CodingKey {
            case provider, code
            case redirectURI = "redirect_uri"
        }
    }

    private struct ResultRequest: Encodable {
        var provider: String
        var state: String
    }

    private struct ErrorResponse: Decodable {
        var error: String?
    }

    private struct StatusResponse: Decodable {
        var providers: [String: IMProviderStatus]
    }
}

/// One provider's setup on the companion, from GET /im/oauth/status.
struct IMProviderStatus: Decodable, Sendable {
    var configured: Bool
    var loginReady: Bool
    var detail: String?
}

/// What a completed login hands back: the profile to show, and the tokens
/// to keep in the keychain. The companion never stores tokens; it only
/// exchanges the code and fetches the profile.
struct IMLoginResult: Decodable, Sendable {
    var displayName: String
    var avatarURL: String?
    var teamName: String?
    var accessToken: String
    var refreshToken: String?
    var expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case teamName = "team_name"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

enum IMAuthError: LocalizedError, Equatable {
    case notPaired
    case noBoxKey
    case companionUnreachable
    case notRegistered
    case providerNotConfigured(platform: String?, detail: String?)
    case cancelled
    case stateMismatch
    case providerRefused(String)
    case invalidCallback
    case invalidAuthorizeURL
    case resultNotReady
    case exchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notPaired:
            return L("需要先配对电脑：陪跑服务跑在你配对的电脑上。")
        case .noBoxKey:
            return L("这台电脑没有配对密钥，请重新配对后再登录。")
        case .companionUnreachable:
            return L("陪跑服务未接通：它跑在你配对的电脑上，现在连不上。")
        case .notRegistered:
            return L("陪跑服务不认这部手机：请重新配对，或让陪跑服务重新登记这部手机。")
        case .providerNotConfigured(_, let detail) where detail == "https-required":
            return L("Slack 登录需要 HTTPS 回调地址，陪跑服务还没有 HTTPS，暂时登不上。")
        case .providerNotConfigured:
            return L("该平台未在陪跑服务里配置：先在浏览器里建好应用，再把它的 ID 与密钥交给陪跑服务。")
        case .cancelled:
            return nil
        case .stateMismatch:
            return L("登录失败，请重试。")
        case .providerRefused:
            return L("登录失败：授权被拒绝。")
        case .invalidCallback, .invalidAuthorizeURL, .resultNotReady:
            return L("登录失败，请重试。")
        case .exchangeFailed(let detail):
            return detail
        }
    }

    /// The user closed the sign-in sheet: silent, no error shown. Same
    /// rule as the account sign-in (AccountStore.isCancellation).
    static func isCancellation(_ error: any Error) -> Bool {
        switch error {
        case let error as ASWebAuthenticationSessionError: error.code == .canceledLogin
        case IMAuthError.cancelled: true
        case is CancellationError: true
        default: false
        }
    }
}

private final class PresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}

private extension URL {
    /// Query items as a dictionary (first value wins).
    var queryDictionary: [String: String] {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return [:] }
        var out: [String: String] = [:]
        for item in items {
            if let value = item.value, out[item.name] == nil { out[item.name] = value }
        }
        return out
    }

    func queryValue(_ name: String) -> String? {
        queryDictionary[name]
    }
}
