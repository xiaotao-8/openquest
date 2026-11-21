import SwiftUI

/// The app's single store. Owns the connector, the persisted settings, and
/// the navigation state. All UI state flows through here; the channel layer
/// never touches SwiftUI.
@MainActor
final class AppStore: ObservableObject {
    let connector = HostConnector()

    // MARK: - Settings (persisted)

    @Published var language: String {
        didSet { UserDefaults.standard.set(language, forKey: L10n.languageKey) }
    }

    @Published var showThinkingDetails: Bool {
        didSet { UserDefaults.standard.set(showThinkingDetails, forKey: "cn.lingyu.showThinkingDetails") }
    }

    @Published var reduceMotion: Bool {
        didSet { UserDefaults.standard.set(reduceMotion, forKey: "cn.lingyu.reduceMotion") }
    }

    /// Appearance: system / light / dark.
    @Published var appearance: String {
        didSet { UserDefaults.standard.set(appearance, forKey: "cn.lingyu.appearance") }
    }

    // MARK: - Navigation

    /// 0 Bots, 1 Discover, 2 State, 3 Settings.
    @Published var selectedTab = 0
    /// The bot whose chat is open (nil = roster).
    @Published var openBotId: String?
    /// The bot whose detail sheet is open.
    @Published var detailBotId: String?
    /// Whether the welcome/pairing flow is showing.
    @Published var showingWelcome = false
    /// Whether the pairing sheet is showing (from Settings or Welcome).
    @Published var showingPairing = false
    /// The Bots tab navigation path (chat pushes append the bot id).
    @Published var navigationPath = NavigationPath()

    // MARK: - Preview

    let previewMode: PreviewMode

    init() {
        language = UserDefaults.standard.string(forKey: L10n.languageKey) ?? "zh"
        showThinkingDetails = UserDefaults.standard.bool(forKey: "cn.lingyu.showThinkingDetails")
        reduceMotion = UserDefaults.standard.bool(forKey: "cn.lingyu.reduceMotion")
        appearance = UserDefaults.standard.string(forKey: "cn.lingyu.appearance") ?? "system"
        previewMode = PreviewMode.fromLaunchArguments()
    }

    var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var isPreview: Bool {
        previewMode != .none
    }

    func start() {
        switch previewMode {
        case .none:
            if connector.isPaired {
                Task { await connector.connectIfPaired() }
            } else {
                showingWelcome = true
            }
        case .seeded(let options):
            PreviewRunner.seed(store: self, options: options)
        case .live:
            Task {
                await PreviewRunner.runLive(store: self)
            }
        }
    }

    func openChat(botId: String) {
        selectedTab = 0
        openBotId = botId
        navigationPath.append(botId)
    }

    func closeChat() {
        openBotId = nil
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        }
    }

    func setLanguage(_ code: String) {
        language = code
    }
}
