import SwiftUI

@main
struct OpenQuestApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            // 回到前台：执行到期的定时任务（本地通知 + 打开 App 后执行，后台常驻跑不了）。
            if phase == .active {
                store.fireDueTasks()
            }
        }
    }
}
