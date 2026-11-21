import AuthenticationServices
import ClerkKit
import Combine
import Foundation

/// The account session. Clerk owns OAuth, session restoration and Keychain
/// persistence: the app never sees, stores, or logs a session token — it
/// asks the SDK for a fresh one on every cloud request.
/// An account session never grants access to a computer by itself: each
/// computer still approves this device, and signing out keeps the local
/// pairing and device key, so signing back in needs no new scan.
@MainActor
final class AccountStore: ObservableObject {
    private let clerk: Clerk?
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?

    /// The account cloud (accounts and the computer lists); nil in builds
    /// without one.
    let cloudURL: URL?

    enum SignInProvider { case apple, google, github }

    enum SessionError: LocalizedError {
        case signedOut
        var errorDescription: String? { L("请重新登录后查看账号内容。") }
    }

    var userID: String? { clerk?.session?.status == .active ? clerk?.user?.id : nil }
    var isConfigured: Bool { clerk != nil }
    /// Clerk restores the persisted Keychain session during configuration.
    /// Don't offer a fresh sign-in until that restore has completed, or an
    /// update can briefly look like a signed-out install.
    var isReady: Bool { clerk?.isLoaded ?? true }
    /// Clerk gave up restoring (launched offline, an outage) and tries again
    /// only when the app comes back to the foreground.
    var restoreFailed: Bool { restoreGaveUp && !isReady }
    private var restoreGaveUp = false

    var isSignedIn: Bool { userID != nil }
    var email: String? { clerk?.user?.primaryEmailAddress?.emailAddress }
    var avatarURL: URL? {
        guard let image = clerk?.user?.imageUrl, let url = URL(string: image), url.scheme == "https" else { return nil }
        return url
    }

    init() {
        let env = ProcessInfo.processInfo.environment
        let config = Bundle.main.url(forResource: "AccountConfig", withExtension: "plist")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? PropertyListDecoder().decode(Configuration.self, from: $0) }
        cloudURL = (env["CODYNC_CLOUD_URL"] ?? config?.cloudURL)
            .flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .flatMap { $0.scheme == "https" && $0.host != nil ? $0 : nil }
        let key = (env["CODYNC_CLERK_PUBLISHABLE_KEY"] ?? config?.clerkPublishableKey ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("pk_test_") || key.hasPrefix("pk_live_") else {
            clerk = nil
            return
        }
        let scheme = Bundle.main.bundleIdentifier ?? "cn.lingyu"
        clerk = Clerk.configure(publishableKey: key, options: .init(
            telemetryEnabled: false,
            redirectConfig: .init(redirectUrl: "\(scheme)://callback", callbackUrlScheme: scheme)
        ))
        // Clerk's own launch refresh tries three times within a few seconds, then only logs.
        Task { restoreGaveUp = !(await waitUntilReady(timeout: .seconds(10))) }
    }

    /// Waits up to `timeout` for the session restore; false when it didn't
    /// finish in time or the task was cancelled.
    func waitUntilReady(timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !isReady, !Task.isCancelled, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return isReady
    }

    /// Clerk's launch refresh again: the environment and the client it
    /// restores sign-in from.
    func retryRestore() async {
        guard let clerk, restoreFailed else { return }
        restoreGaveUp = false
        _ = try? await clerk.refreshEnvironment()
        _ = try? await clerk.refreshClient()
        restoreGaveUp = !isReady
    }

    /// The signed-in session's JWT for the account cloud (Clerk caches it
    /// for about a minute). Fetched fresh on every call; never stored.
    func sessionToken() async throws -> String {
        guard let clerk, isSignedIn, let token = try await clerk.auth.getToken() else { throw SessionError.signedOut }
        return token
    }

    /// The account cloud for `userID`; nil when signed out or the build has
    /// no cloud. Requests stop working once another account becomes active,
    /// so one account's calls never carry another's token.
    func cloudClient(for userID: String?) -> CloudClient? {
        guard let userID, let cloudURL, isConfigured else { return nil }
        return CloudClient(baseURL: cloudURL) { [weak self] in
            guard let self, await self.userID == userID else { throw SessionError.signedOut }
            return try await self.sessionToken()
        }
    }

    /// The cloud for the currently signed-in account, if any.
    func cloudClient() -> CloudClient? {
        cloudClient(for: userID)
    }

    func signIn(provider: SignInProvider) async {
        guard !isBusy else { return }
        guard let clerk else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            // Every provider uses Clerk's transfer flow and activates the same kind of session.
            let result: TransferFlowResult
            switch provider {
            case .apple:
                result = try await clerk.auth.signInWithApple()
            case .google:
                result = try await clerk.auth.signInWithOAuth(provider: .google, prefersEphemeralWebBrowserSession: isSignedIn)
            case .github:
                result = try await clerk.auth.signInWithOAuth(provider: .github, prefersEphemeralWebBrowserSession: isSignedIn)
            }
            switch result {
            case .signIn(let signIn):
                if signIn.status != .complete {
                    errorMessage = L("登录需要补充验证，账号尚未登录。")
                }
            case .signUp(let signUp):
                if signUp.status != .complete {
                    errorMessage = L("注册需要补充信息，账号尚未登录。")
                }
            }
        } catch where Self.isCancellation(error) {
            // The user closed the sign-in sheet: silent, no error shown.
        } catch {
            errorMessage = L("登录失败，请检查网络后重试。")
        }
    }

    /// The user closed the sign-in sheet.
    private static func isCancellation(_ error: any Error) -> Bool {
        switch error {
        case let error as ASWebAuthenticationSessionError: error.code == .canceledLogin
        case let error as ASAuthorizationError: error.code == .canceled
        default: error is CancellationError
        }
    }

    /// Signs out of the current session. The local pairing and device key
    /// stay on this phone, so signing back in needs no new scan; the
    /// account's computers just stop sending this phone alerts until then.
    func signOut() async {
        guard !isBusy, let clerk, let sessionID = clerk.session?.id else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await clerk.auth.signOut(sessionId: sessionID)
        } catch {
            errorMessage = L("登出失败，请检查网络后重试。")
        }
    }

    /// Every account on this device, for starting over. Local computers are
    /// forgotten separately by the caller; this only ends the sessions.
    func signOutAll() async {
        guard let clerk else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        for session in clerk.auth.sessions {
            try? await clerk.auth.signOut(sessionId: session.id)
        }
    }

    /// Deletes the signed-in user in Clerk (the cloud cleans up after
    /// Clerk's `user.deleted`). Throws when Clerk refused or couldn't be
    /// reached, and then nothing changed.
    func deleteUser() async throws {
        guard let clerk, let user = clerk.user, let sessionID = clerk.session?.id else { throw SessionError.signedOut }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        try await user.delete()
        // Clerk ends the session with the user; make sure it's gone here too.
        if userID == user.id { try? await clerk.auth.signOut(sessionId: sessionID) }
    }

    /// Finishes a sign-in that came back through the app's callback URL.
    func handle(_ url: URL) async {
        guard let clerk else { return }
        do { try await clerk.handle(url) }
        catch { errorMessage = L("无法完成登录，请重试。") }
    }

    /// `AccountConfig.plist` (`CODYNC_CLERK_PUBLISHABLE_KEY` /
    /// `CODYNC_CLOUD_URL` override it).
    private struct Configuration: Decodable {
        let clerkPublishableKey: String?
        let cloudURL: String?
    }
}
