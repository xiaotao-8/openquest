import SwiftUI

@main
struct LinGyUApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(store.colorScheme)
                .onAppear {
                    store.start()
                }
                .onOpenURL { url in
                    // The account sign-in callback (scheme is the bundle id).
                    // Pairing links are handled in-app, never through here.
                    if url.scheme == Bundle.main.bundleIdentifier {
                        Task { await store.account.handle(url) }
                    }
                }
        }
    }
}
