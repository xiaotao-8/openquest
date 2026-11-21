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
        }
    }
}
