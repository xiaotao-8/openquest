import SwiftUI

/// 聊天跳转目标：会话 id + 首页带来的首条消息（带附件）。
struct ChatDestination: Hashable {
    let id: UUID
    let firstMessage: String?
    let image: Data?
    let fileName: String?
    let fileText: String?
    init(id: UUID, firstMessage: String? = nil, image: Data? = nil,
         fileName: String? = nil, fileText: String? = nil) {
        self.id = id
        self.firstMessage = firstMessage
        self.image = image
        self.fileName = fileName
        self.fileText = fileText
    }
}

/// 根视图：FishPocket 式壳——底部悬浮四图标 Tab（会话 / 智能体 / 我的应用 / 探索），
/// 图标-only、无文字；会话 Tab 里是首页（新会话）与聊天页，聊天时 Tab 栏收起。
/// 会话列表与设置走首页左上角 chevron 打开的抽屉式列表。
struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var tab = 0
    @State private var chatPath: [ChatDestination] = []
    @State private var showSessions = false
    @State private var showSettings = false
    @State private var updateFeed: UpdateChecker.Feed?

    private func L(_ key: String) -> String { L10n.t(key, lang: store.language) }

    /// 智能体 Tab 上的红点：正在干活的会话数。
    private var workingBadge: Int {
        store.conversations.filter { $0.workingNote != nil }.count
    }

    var body: some View {
        // 预览专用：-PreviewDNS 直接落在 DNS 页截图。
        if ProcessInfo.processInfo.arguments.contains("-PreviewDNS") {
            NavigationStack { DNSSettingsView() }
        } else if ProcessInfo.processInfo.arguments.contains("-PreviewProviders") {
            // 预览专用：-PreviewProviders 直接落在供应商页截图，验免费 Agnes 添加。
            NavigationStack { ProvidersView() }
        } else {
            ZStack(alignment: .bottom) {
                Group {
                    switch tab {
                    case 1:
                        NavigationStack { AgentsView() }
                    case 2:
                        NavigationStack { MiniAppsView() }
                    case 3:
                        ExploreView()
                    default:
                        NavigationStack(path: $chatPath) {
                            HomeView(
                                onOpenSessions: { showSessions = true },
                                onOpenConversation: { chatPath.append($0) }
                            )
                            .navigationDestination(for: ChatDestination.self) { dest in
                                ChatView(conversationId: dest.id,
                                         initialMessage: dest.firstMessage,
                                         initialImage: dest.image,
                                         initialFileName: dest.fileName,
                                         initialFileText: dest.fileText)
                            }
                        }
                    }
                }
                if !(tab == 0 && !chatPath.isEmpty) {
                    tabBar
                        .padding(.bottom, 26)
                }
            }
            .background(Palette.background)
            .sheet(isPresented: $showSessions) {
                NavigationStack {
                    ChatListView(
                        onOpen: { id in
                            showSessions = false
                            chatPath.append(ChatDestination(id: id))
                        },
                        onOpenSettings: {
                            showSessions = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                showSettings = true
                            }
                        }
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { showSessions = false }
                        }
                    }
                }
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(36)
            }
            .fullScreenCover(isPresented: $showSettings) {
                SettingsCover()
            }
            .onAppear {
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-PreviewSettings") {
                    // sheet/cover 在首现 onAppear 里同步置位会被 SwiftUI 丢掉，
                    // 必须异步抛到下一轮 runloop 才能正常弹出（实测 #25 两张图因此没出）。
                    DispatchQueue.main.async { showSettings = true }
                } else if (args.contains("-PreviewChat") || args.contains("-PreviewLiveChat")),
                          let first = store.conversations.first, chatPath.isEmpty {
                    // 仅模拟器预览截图用：直接进第一个会话（演示数据里的团队群）。
                    chatPath = [ChatDestination(id: first.id)]
                } else if args.contains("-PreviewSeed") {
                    // 仅模拟器预览截图用：-PreviewSeed 单独出现 = 打开会话列表。
                    DispatchQueue.main.async { showSessions = true }
                }
            }
            .task {
                // 云更新：每次打开 App 查一次版本源，有新版弹窗提示下载。
                // 模拟器预览截图（-Preview*）不查，不然弹窗会盖住截图。
                let args = ProcessInfo.processInfo.arguments
                guard !args.contains(where: { $0.hasPrefix("-Preview") }) else { return }
                if case .available(let feed) = await UpdateChecker.check() {
                    updateFeed = feed
                }
            }
            .alert("有新版本", isPresented: Binding(
                get: { updateFeed != nil },
                set: { if !$0 { updateFeed = nil } }
            )) {
                Button("去下载") {
                    if let urlString = updateFeed?.url, let url = URL(string: urlString) {
                        UIApplication.shared.open(url)
                    }
                    updateFeed = nil
                }
                Button("稍后再说", role: .cancel) { updateFeed = nil }
            } message: {
                Text(updateFeed?.notes.isEmpty == false ? updateFeed!.notes : "下载新包后去签名工具重签安装。")
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            tabButton(0, icon: "message", label: L("tab_chat"))
            tabButton(1, ghost: true, label: L("tab_agents"), badge: workingBadge)
            tabButton(2, icon: "square.on.square", label: L("tab_apps"))
            tabButton(3, icon: "square.grid.2x2", label: L("tab_explore"))
        }
        .padding(5)
        .floatingGlass()
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
    }

    private func tabButton(_ index: Int, icon: String? = nil, ghost: Bool = false,
                           label: String, badge: Int = 0) -> some View {
        Button {
            if index == 0 { chatPath = [] }
            tab = index
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if ghost {
                        GhostIcon()
                    } else if let icon {
                        Image(systemName: tab == index ? icon + ".fill" : icon)
                            .font(.system(size: 21))
                            .foregroundStyle(Palette.ink)
                    }
                }
                .frame(width: 56, height: 48)
                .background(tab == index ? Palette.control : Color.clear,
                            in: RoundedRectangle(cornerRadius: 16))
                if badge > 0 {
                    Text("\(min(badge, 99))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                        .offset(x: 6, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// 设置全屏页（FishPocket 设置 sheet 同款：右上角白圆 X 关闭）。
private struct SettingsCover: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SettingsView()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 40, height: 40)
                    .background(Palette.background, in: Circle())
                    .overlay(Circle().stroke(Palette.stroke, lineWidth: 1))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.top, 54)
            .padding(.trailing, 16)
        }
    }
}

/// 设置页：iOS 设置同款排法——彩色方图标 + 名字 + 值/箭头。
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: AppStore

    private func L(_ key: String) -> String { L10n.t(key, lang: store.language) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SettingRow(icon: "person.2.fill", color: .purple, title: L("agents"),
                               value: store.agents.isEmpty ? nil : "\(store.agents.count)") {
                        AgentsView()
                    }
                    SettingRow(icon: "cube.fill", color: .blue, title: L("providers"),
                               value: store.providers.isEmpty ? nil : "\(store.providers.count)") {
                        ProvidersView()
                    }
                    SettingRow(icon: "wand.and.stars", color: .pink, title: L("skills"),
                               value: store.skills.isEmpty ? nil : "\(store.skills.count)") {
                        SkillsView()
                    }
                    SettingRow(icon: "puzzlepiece.fill", color: .indigo, title: L("plugins"),
                               value: store.plugins.isEmpty ? nil : "\(store.plugins.count)") {
                        PluginsView()
                    }
                    SettingRow(icon: "network", color: .teal, title: L("dns"),
                               value: store.dnsMode == "system" ? "跟随系统" : nil) {
                        DNSSettingsView()
                    }
                    SettingRow(icon: "link", color: .orange, title: L("connectors"),
                               value: store.connectors.contains { $0.enabled } ? nil : "全部关") {
                        ConnectorsView()
                    }
                    SettingRow(icon: "safari.fill", color: .cyan, title: L("server_browser")) {
                        BrowserView()
                    }
                }
                Section {
                    SettingRow(icon: "alarm.fill", color: .red, title: L("schedules"),
                               value: store.scheduledTasks.isEmpty ? nil : "\(store.scheduledTasks.count)") {
                        SchedulesView()
                    }
                    SettingRow(icon: "square.on.circle", color: .mint, title: L("mini_apps"),
                               value: store.miniApps.isEmpty ? nil : "\(store.miniApps.count)") {
                        MiniAppsView()
                    }
                    SettingRow(icon: "globe", color: .brown, title: L("language"),
                               value: L10n.languages.first { $0.code == store.language }?.name) {
                        LanguageSettingsView()
                    }
                    SettingRow(icon: "chart.bar.fill", color: .green, title: L("usage"),
                               value: "\(store.totalUsage.prompt + store.totalUsage.completion)") {
                        UsageStatsView()
                    }
                    SettingRow(icon: "arrow.down.circle.fill", color: .blue, title: L("update")) {
                        UpdateView()
                    }
                    SettingRow(icon: "iphone", color: .gray, title: L("device_caps"),
                               value: store.deviceCapabilities.contains { $0.enabled } ? nil : "全部关") {
                        DeviceCapabilitiesView()
                    }
                }
                Section {
                    SettingRow(icon: "doc.text.fill", color: .gray, title: L("log")) {
                        LogView()
                    }
                }
            }
            .navigationTitle(L("settings"))
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

/// 连接工具：只列国内服务，全部默认关，用户手动开；每个可填 Key/Token，
/// 点“测试”走一次真实调用，通过才算连上。自定义 MCP 另外加。
struct ConnectorsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        List {
            ForEach(store.connectors) { c in
                ConnectorRow(connector: c)
            }
            Section("自定义 MCP（你自己的 MCP 服务器，HTTPS 地址）") {
                ForEach(store.customMCPs) { m in
                    CustomMCPRow(mcp: m)
                }
                .onDelete { idx in
                    for i in idx { store.deleteCustomMCP(id: store.customMCPs[i].id) }
                }
                AddMCPRow()
            }
            Section {
                Text("只装国内服务，全部默认关，开哪个用哪个。Key 只存系统钥匙串。测试走一次真实调用，通过才算连上。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("连接工具")
    }
}

private struct ConnectorRow: View {
    @EnvironmentObject var store: AppStore
    let connector: Connector
    @State private var credText = ""
    @State private var status: String?
    @State private var busy = false
    @State private var showCred = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { connector.enabled },
                set: { store.setConnectorEnabled(id: connector.id, $0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(connector.name)
                    Text(connector.summary).font(.caption).foregroundStyle(.secondary)
                }
            }
            if connector.id == "aliyun" {
                Text("阿里云暂只留开关：调用要 AK/SK 签名，App 内还没接。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button(showCred ? "收起 Key" : (hasCred ? "改 Key（已填）" : "填 Key / Token")) {
                    showCred.toggle()
                    if showCred {
                        credText = KeychainHelper.key(ref: "connector-\(connector.id)") ?? ""
                    }
                }
                .font(.subheadline)
                if showCred {
                    SecureField(placeholder, text: $credText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    HStack {
                        Button("保存") {
                            KeychainHelper.setKey(
                                credText.trimmingCharacters(in: .whitespaces),
                                ref: "connector-\(connector.id)")
                            showCred = false
                            status = "已保存到钥匙串"
                        }
                        .disabled(credText.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("测试") { Task { await runTest() } }
                            .disabled(busy)
                        if busy { ProgressView() }
                    }
                    .font(.subheadline)
                }
                if let status {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var hasCred: Bool {
        !(KeychainHelper.key(ref: "connector-\(connector.id)") ?? "").isEmpty
    }

    private var placeholder: String {
        switch connector.id {
        case "feishu": return "App ID:App Secret（冒号隔开）"
        case "dingtalk": return "AppKey:AppSecret（冒号隔开）"
        case "yuque": return "语雀 Token"
        case "gitee": return "Gitee Token"
        case "bocha": return "博查 API Key"
        default: return "Key / Token"
        }
    }

    private func runTest() async {
        busy = true
        defer { busy = false }
        let cred = KeychainHelper.key(ref: "connector-\(connector.id)") ?? ""
        status = await ConnectorTest.test(id: connector.id, credential: cred)
    }
}

private struct CustomMCPRow: View {
    @EnvironmentObject var store: AppStore
    let mcp: CustomMCP
    @State private var status: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { mcp.enabled },
                set: { store.setCustomMCPEnabled(id: mcp.id, $0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mcp.name)
                    Text(mcp.url).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("测试") { Task { await test() } }.disabled(busy)
                if busy { ProgressView() }
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }

    private func test() async {
        busy = true
        defer { busy = false }
        status = await ConnectorTest.testMCP(url: mcp.url)
    }
}

private struct AddMCPRow: View {
    @EnvironmentObject var store: AppStore
    @State private var name = ""
    @State private var url = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("名字，如：我的 MCP", text: $name)
            TextField("HTTPS 地址，如 https://example.com/mcp", text: $url)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            Button("添加") {
                store.addCustomMCP(name: name.trimmingCharacters(in: .whitespaces),
                                   url: url.trimmingCharacters(in: .whitespaces))
                name = ""
                url = ""
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                      || url.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

