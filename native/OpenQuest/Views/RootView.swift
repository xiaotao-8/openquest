import SwiftUI

/// 根视图：聊天列表为主，左上进设置（供应商、服务器、连接工具都在设置里）。
struct RootView: View {
    @State private var path: [UUID] = []
    @State private var showingSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            ChatListView()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showingSettings = true } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
                .navigationDestination(for: UUID.self) { id in
                    ChatView(conversationId: id)
                }
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("智能体") { AgentsView() }
                NavigationLink("供应商与模型") { ProvidersView() }
                NavigationLink("服务器") { ServerView() }
                NavigationLink("连接工具") { ConnectorsView() }
                NavigationLink("浏览器") { BrowserView() }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

/// 连接工具：只列国内服务，全部默认关，用户手动开。
struct ConnectorsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        List {
            ForEach(store.connectors) { c in
                Toggle(isOn: Binding(
                    get: { c.enabled },
                    set: { store.setConnectorEnabled(id: c.id, $0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name)
                        Text(c.summary).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Text("只装国内服务，全部默认关，开哪个用哪个。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("连接工具")
    }
}
