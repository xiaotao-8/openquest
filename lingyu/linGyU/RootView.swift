import SwiftUI

/// The 4-tab root: Bots / Discover / State / Settings. The welcome flow
/// replaces the tabs until the user pairs or skips. Chat pushes inside the
/// Bots tab's NavigationStack and hides the tab bar.
struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        if case .seeded(let options) = store.previewMode, let pairingPage = options.pairingPage {
            PairingView(initialStep: pairingPage == "scan" ? .scan : .install)
        } else if case .seeded(let options) = store.previewMode, options.computers {
            ComputersView()
        } else if case .seeded(let options) = store.previewMode, options.extensions {
            ExtensionsView()
        } else if case .seeded(let options) = store.previewMode, options.hostNetwork {
            NetworkView()
        } else if case .seeded(let options) = store.previewMode, options.usage {
            HostUsageView()
        } else if case .seeded(let options) = store.previewMode, options.imBridge {
            IMBridgeView()
        } else if case .seeded(let options) = store.previewMode, options.phoneControl {
            PhoneControlView()
        } else if case .seeded(let options) = store.previewMode, options.botImport {
            BotImportView()
        } else if case .seeded(let options) = store.previewMode, options.computerUse {
            ComputerUseView()
        } else if store.showingWelcome && !store.connector.isPaired && !store.isPreview {
            WelcomeView(onSkip: {
                store.showingWelcome = false
            })
        } else {
            TabView(selection: $store.selectedTab) {
                NavigationStack(path: $store.navigationPath) {
                    BotListView()
                        .navigationDestination(for: String.self) { botId in
                            ChatView(botId: botId)
                                .toolbar(.hidden, for: .tabBar)
                        }
                }
                .tabItem {
                    Label(L("智能体"), systemImage: "bubble.left.and.bubble.right.fill")
                }
                .tag(0)

                DiscoverView()
                    .tabItem {
                        Label(L("发现"), systemImage: "sparkles")
                    }
                    .tag(1)

                StateView()
                    .tabItem {
                        Label(L("状态"), systemImage: "rectangle.stack.fill")
                    }
                    .tag(2)

                SettingsView()
                    .tabItem {
                        Label(L("设置"), systemImage: "gearshape")
                    }
                    .tag(3)
            }
            .tint(Palette.text)
            .overlay(alignment: .top) {
                if store.showLiveDiag {
                    LiveDiagOverlayView(diag: store.liveDiag)
                }
            }
            .codyncSheet(isPresented: $store.showingPairing) {
                PairingView(inModal: true)
            }
            .codyncSheet(isPresented: Binding(
                get: { store.detailBotId != nil },
                set: { if !$0 { store.detailBotId = nil } }
            )) {
                if let botId = store.detailBotId, let bot = store.connector.mirror.bot(id: botId) {
                    BotDetailsView(bot: bot)
                }
            }
        }
    }
}
