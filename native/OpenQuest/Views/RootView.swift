import SwiftUI

/// 根视图：聊天列表为主，左上进设置（供应商、服务器、连接工具都在设置里）。
struct RootView: View {
    @State private var path: [UUID] = []
    @State private var showingSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            ChatListView(path: $path)
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

/// 设置页：iOS 设置同款排法——彩色方图标 + 名字 + 值/箭头。
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SettingRow(icon: "person.2.fill", color: .purple, title: "智能体",
                               value: store.agents.isEmpty ? nil : "\(store.agents.count)") {
                        AgentsView()
                    }
                    SettingRow(icon: "cube.fill", color: .blue, title: "供应商与模型",
                               value: store.providers.isEmpty ? nil : "\(store.providers.count)") {
                        ProvidersView()
                    }
                    SettingRow(icon: "server.rack", color: .green, title: "服务器",
                               value: store.server.host) {
                        ServerView()
                    }
                    SettingRow(icon: "link", color: .orange, title: "连接工具",
                               value: store.connectors.contains { $0.enabled } ? nil : "全部关") {
                        ConnectorsView()
                    }
                    SettingRow(icon: "safari.fill", color: .cyan, title: "服务器浏览器") {
                        BrowserView()
                    }
                }
                Section {
                    SettingRow(icon: "doc.text.fill", color: .gray, title: "日志") {
                        LogView()
                    }
                }
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

private struct SettingRow<Destination: View>: View {
    let icon: String
    let color: Color
    let title: String
    var value: String? = nil
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .frame(width: 29, height: 29)
                    .background(color, in: RoundedRectangle(cornerRadius: 7))
                Text(title)
                Spacer()
                if let value {
                    Text(value).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// 日志页（关于只留日志，用户定的）。
struct LogView: View {
    var body: some View {
        ContentUnavailableView("暂无日志", systemImage: "doc.text",
                               description: Text("应用运行日志会记在这里。"))
            .navigationTitle("日志")
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
