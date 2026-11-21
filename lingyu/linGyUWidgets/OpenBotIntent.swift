import AppIntents

/// A widget button that opens one bot's conversation, one Space, or a
/// new chat. A plain `OpenURLIntent` from a widget button does not
/// launch the app for a custom scheme, so this intent is built into the
/// app as well and runs there (`openAppWhenRun`), handing the deep link
/// to `open` (the original's pattern, same reason).
struct OpenBotIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Bot"
    static let isDiscoverable = false
    static let openAppWhenRun = true

    /// Set by the app at launch; the widget extension never runs `perform`.
    @MainActor static var open: (URL) -> Void = { _ in }

    @Parameter(title: "Link") var url: URL

    init() {}

    init(_ url: URL) { self.url = url }

    @MainActor func perform() async throws -> some IntentResult {
        Self.open(url)
        return .result()
    }
}

/// A Live Activity button that opens the approvals page (optionally one
/// pending entry). The decision itself is always made inside the app:
/// the extension never answers an approval, it only opens the page.
/// Direct in-island approve/deny needs the pairing key in the shared
/// container, which is out of scope for this round (see the gap list).
struct OpenApprovalIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Approval"
    static let isDiscoverable = false
    static let openAppWhenRun = true

    /// Set by the app at launch; the extension never runs `perform`.
    @MainActor static var open: (URL) -> Void = { _ in }

    @Parameter(title: "Link") var url: URL

    init() {}

    init(entryId: String) { self.url = WidgetDeepLink.approvals(entryId) }

    init(_ url: URL) { self.url = url }

    @MainActor func perform() async throws -> some IntentResult {
        Self.open(url)
        return .result()
    }
}
