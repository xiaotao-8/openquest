import SwiftUI

@main
struct OpenQuestApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        LogStore.append("启动", "OpenQuest 已启动")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onOpenURL { url in
                    // 锁屏审批点允许/拒绝：openquest://approval?conv=<id>&choice=allow|deny
                    guard url.scheme == "openquest", url.host == "approval",
                          let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                          let conv = items.first(where: { $0.name == "conv" })?.value,
                          let convId = UUID(uuidString: conv),
                          let choice = items.first(where: { $0.name == "choice" })?.value
                    else { return }
                    store.openConversationId = convId
                    store.deepLinkApproval = DeepLinkApproval(
                        convId: convId, approve: choice == "allow")
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // 回到前台：执行到期的定时任务（本地通知 + 打开 App 后执行，后台常驻跑不了）。
            if phase == .active {
                store.fireDueTasks()
            }
        }
    }
}
