import Foundation

/// Deep links into the app. The scheme is the bundle id (`cn.lingyu`,
/// already registered in the app's Info.plist), so no new scheme is
/// needed. The app side of each link is the coordinator's job
/// (see `appstore-additions.swift`): the widget and the Live Activity
/// only ever hand the app a URL, they never act on it themselves.
enum WidgetDeepLink {
    static let scheme = "cn.lingyu"

    /// Open one bot's chat.
    static func bot(_ id: String) -> URL { url(host: "bot", path: "/\(id)") }

    /// Open a new chat with the lead bot.
    static func newChat() -> URL { url(host: "new-chat", path: "") }

    /// Open one Space (mini-app) in Discover.
    static func space(_ id: String) -> URL { url(host: "space", path: "/\(id)") }

    /// Open the approvals list, or one pending entry when given.
    static func approvals(_ entryId: String? = nil) -> URL {
        url(host: "approvals", path: entryId.map { "/\($0)" } ?? "")
    }

    /// Open the call view for a bot; `action` is "mute" or "end" when a
    /// call-control intent asks the app to act (the extension itself
    /// never touches the call).
    static func call(_ botId: String, action: String? = nil) -> URL {
        var components = urlComponents(host: "call", path: "/\(botId)")
        if let action { components.queryItems = [URLQueryItem(name: "action", value: action)] }
        return components.url ?? fallback(host: "call")
    }

    private static func url(host: String, path: String) -> URL {
        urlComponents(host: host, path: path).url ?? fallback(host: host)
    }

    private static func urlComponents(host: String, path: String) -> URLComponents {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        return components
    }

    private static func fallback(host: String) -> URL {
        URL(string: "\(scheme)://\(host)")!
    }
}
