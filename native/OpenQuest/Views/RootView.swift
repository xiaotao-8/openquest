import SwiftUI

/// 根视图：聊天为主页，底部悬浮玻璃标签栏（聊天 / 技能 / 浏览器 / 设置），
/// 跟 Muse App 一样的壳。进聊天后标签栏还在，点标签回主页切页。
struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var path: [UUID] = []
    @State private var tab = 0

    var body: some View {
        // 预览专用：-PreviewDNS 直接落在 DNS 页截图。
        if ProcessInfo.processInfo.arguments.contains("-PreviewDNS") {
            NavigationStack { DNSSettingsView() }
        } else {
            ZStack(alignment: .bottom) {
                Group {
                    switch tab {
                    case 1:
                        NavigationStack { SkillsView() }
                    case 2:
                        NavigationStack { BrowserView() }
                    case 3:
                        SettingsView()
                    default:
                        NavigationStack(path: $path) {
                            ChatListView(path: $path)
                                .navigationDestination(for: UUID.self) { id in
                                    ChatView(conversationId: id)
                                }
                        }
                    }
                }
                tabBar
                    .padding(.bottom, 26)
            }
            .background(Color.black)
            .onAppear {
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-PreviewSettings") { tab = 3 }
                // 仅模拟器预览截图用：直接进第一个会话（演示数据里的团队群）。
                if args.contains("-PreviewChat"),
                   let first = store.conversations.first, path.isEmpty {
                    path = [first.id]
                }
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            tabButton(0, icon: "message.fill", label: "聊天")
            tabButton(1, icon: "wand.and.stars", label: "技能")
            tabButton(2, icon: "globe", label: "浏览器")
            tabButton(3, icon: "gearshape.fill", label: "设置")
        }
        .padding(5)
        .liquidGlass(Capsule())
        .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
    }

    private func tabButton(_ index: Int, icon: String, label: String) -> some View {
        Button {
            if index == 0 { path = [] }
            tab = index
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 19))
                Text(label).font(.system(size: 9.5))
            }
            .frame(width: 62, height: 44)
            .background(tab == index ? Color.white.opacity(0.13) : Color.clear,
                        in: Capsule())
            .foregroundStyle(tab == index ? .white : .secondary)
        }
        .buttonStyle(.plain)
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
                    SettingRow(icon: "wand.and.stars", color: .pink, title: "技能",
                               value: store.skills.isEmpty ? nil : "\(store.skills.count)") {
                        SkillsView()
                    }
                    SettingRow(icon: "puzzlepiece.fill", color: .indigo, title: "插件",
                               value: store.plugins.isEmpty ? nil : "\(store.plugins.count)") {
                        PluginsView()
                    }
                    SettingRow(icon: "network", color: .teal, title: "DNS",
                               value: store.dnsMode == "system" ? "跟随系统" : nil) {
                        DNSSettingsView()
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
