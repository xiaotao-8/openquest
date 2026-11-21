import AppIntents

/// The call Live Activity's buttons. Like the other widget intents,
/// these run in the app (`openAppWhenRun`): they hand the app a deep
/// link (`cn.lingyu://call/<botId>?action=mute|end`) and the app's call
/// layer acts on it. The extension never touches the call itself, and
/// the buttons do nothing until the app wires the `action` query item
/// (see `appstore-additions.swift`).
struct MuteCallIntent: AppIntent {
    static let title: LocalizedStringResource = "Mute Call"
    static let isDiscoverable = false
    static let openAppWhenRun = true

    /// Set by the app at launch; the extension never runs `perform`.
    @MainActor static var open: (URL) -> Void = { _ in }

    @Parameter(title: "Bot") var botId: String

    init() { self.botId = "" }

    init(botId: String) { self.botId = botId }

    @MainActor func perform() async throws -> some IntentResult {
        Self.open(WidgetDeepLink.call(botId, action: "mute"))
        return .result()
    }
}

struct EndCallIntent: AppIntent {
    static let title: LocalizedStringResource = "End Call"
    static let isDiscoverable = false
    static let openAppWhenRun = true

    /// Set by the app at launch; the extension never runs `perform`.
    @MainActor static var open: (URL) -> Void = { _ in }

    @Parameter(title: "Bot") var botId: String

    init() { self.botId = "" }

    init(botId: String) { self.botId = botId }

    @MainActor func perform() async throws -> some IntentResult {
        Self.open(WidgetDeepLink.call(botId, action: "end"))
        return .result()
    }
}
