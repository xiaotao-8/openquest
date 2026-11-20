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

    /// 设置页逐项验收截图：-PreviewPage=<key> 落到的页面（无参构造，全部取 store）。
    @ViewBuilder
    private func previewPageView(_ page: String) -> some View {
        switch page {
        case "agents": AgentsView()
        case "skills": SkillsView()
        case "plugins": PluginsView()
        case "connectors": ConnectorsView()
        case "browser": BrowserView()
        case "schedules": SchedulesView()
        case "miniapps": MiniAppsView()
        case "language": LanguageSettingsView()
        case "usage": UsageView()
        case "soul": SoulView()
        case "memory": GlobalMemoryView()
        case "envvars": EnvVarsView()
        case "update": UpdateView()
        case "devicecaps": DeviceCapabilitiesView()
        case "group": GroupSettingsView(
            conversationId: store.conversations.first(where: { $0.isGroup })?.id ?? UUID())
        default: HomeView(onOpenSessions: {}, onOpenConversation: { _ in })
        }
    }

    /// 智能体 Tab 上的红点：正在干活的会话数。
    private var workingBadge: Int {
        store.conversations.filter { $0.workingNote != nil }.count
    }

    var body: some View {
        // 预览专用：-PreviewDNS 直接落在 DNS 页截图。
        if ProcessInfo.processInfo.arguments.contains("-PreviewDNS") {
            NavigationStack { DNSSettingsView() }
        } else if ProcessInfo.processInfo.arguments.contains("-PreviewPermissions") {
            // 预览专用：-PreviewPermissions 直接落在权限页截图，不用多步点按。
            NavigationStack { PermissionsView() }
        } else if ProcessInfo.processInfo.arguments.contains("-PreviewProviders") {
            // 预览专用：-PreviewProviders 直接落在供应商页截图，验用户自己加供应商。
            NavigationStack { ProvidersView() }
        } else if ProcessInfo.processInfo.arguments.contains("-PreviewLog") {
            // 预览专用：-PreviewLog 直接落在日志页截图，验日志真记了启动记录。
            NavigationStack { LogView() }
        } else if let page = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-PreviewPage=") })?.dropFirst("-PreviewPage=".count) {
            // 预览专用：-PreviewPage=<key> 直接落到设置页里某一项的页面，一项一张截图。
            NavigationStack { previewPageView(String(page)) }
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
                } else if (args.contains("-PreviewChat") || args.contains("-PreviewLiveChat")
                           || args.contains("-PreviewAsk") || args.contains("-PreviewApproval")),
                          let first = store.conversations.first, chatPath.isEmpty {
                    // 仅模拟器预览截图用：直接进第一个会话（演示数据里的团队群）。
                    // -PreviewAsk 也走这里：进聊天页后 ChatView.onAppear 再注提问卡种子。
                    // -PreviewApproval 同理：进聊天页后 ChatView.onAppear 再注审批卡种子。
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

/// 设置页（FishPocket 设置页结构：灰底 + 白底大圆角分组卡片 + 大号粗体标题；
/// 只学结构，内容是我们自己的中文。图标一律细线黑白线形、无彩色方块底——
/// 原版就是极简黑白线形图标，彩色方块是廉价感的来源）。
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: AppStore
    @ObservedObject private var permissions = PermissionsStore.shared

    private func L(_ key: String) -> String { L10n.t(key, lang: store.language) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L("settings"))
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .padding(.top, 96)
                        .padding(.leading, 20)
                        .padding(.bottom, 20)

                    // 第一张卡：智能体 / 供应商与模型 / 默认访问模式 / 技能 / 插件 / DNS / 连接工具 / 服务器浏览器。
                    SettingsCard {
                        SettingRow(icon: "person.2", title: L("agents"),
                                   value: store.agents.isEmpty ? nil : "\(store.agents.count)") {
                            AgentsView()
                        }
                        SettingRow(icon: "cube", title: L("providers"),
                                   value: store.providers.isEmpty ? nil : "\(store.providers.count)") {
                            ProvidersView()
                        }
                        SettingRow(icon: "lock.shield", title: "默认访问模式",
                                   value: permissions.accessModeDescription,
                                   accessory: .upDownChevrons) {
                            PermissionsView()
                        }
                        SettingRow(icon: "lock.shield.fill", title: "权限") {
                            PermissionsView()
                        }
                        SettingRow(icon: "wand.and.stars", title: L("skills"),
                                   value: store.skills.isEmpty ? nil : "\(store.skills.count)") {
                            SkillsView()
                        }
                        SettingRow(icon: "puzzlepiece", title: L("plugins"),
                                   value: store.plugins.isEmpty ? nil : "\(store.plugins.count)") {
                            PluginsView()
                        }
                        SettingRow(icon: "network", title: L("dns"),
                                   value: store.dnsMode == "system" ? "跟随系统" : nil) {
                            DNSSettingsView()
                        }
                        SettingRow(icon: "link", title: L("connectors"),
                                   value: store.connectors.contains { $0.enabled } ? nil : "全部关") {
                            ConnectorsView()
                        }
                        SettingRow(icon: "safari", title: L("server_browser"), showsDivider: false) {
                            BrowserView()
                        }
                    }
                    Text("每个供应商都能独立用，配好一个、填上 Key 就能开始聊天。")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.leading, 36).padding(.top, 8)

                    // 第二张卡：定时任务 / 小工具 / 语言 / 用量统计。
                    SettingsCard {
                        SettingRow(icon: "alarm", title: L("schedules"),
                                   value: store.scheduledTasks.isEmpty ? nil : "\(store.scheduledTasks.count)") {
                            SchedulesView()
                        }
                        SettingRow(icon: "square.on.square", title: L("mini_apps"),
                                   value: store.miniApps.isEmpty ? nil : "\(store.miniApps.count)") {
                            MiniAppsView()
                        }
                        SettingRow(icon: "globe", title: L("language"),
                                   value: L10n.languages.first { $0.code == store.language }?.name) {
                            LanguageSettingsView()
                        }
                        SettingRow(icon: "chart.bar", title: L("usage"),
                                   value: "\(store.totalUsage.prompt + store.totalUsage.completion)", showsDivider: false) {
                            UsageView()
                        }
                    }
                    .padding(.top, 24)

                    // 智能体运行时分组：Soul / 记忆 / 环境变量（技能只在第一张卡出现，不重复）。
                    Text("智能体运行时")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 36).padding(.top, 28).padding(.bottom, 8)
                    SettingsCard {
                        SettingRow(icon: "heart.text.square", title: "Soul",
                                   value: store.soulText.isEmpty ? "未写" : "已写") {
                            SoulView()
                        }
                        SettingRow(icon: "brain", title: "记忆",
                                   value: store.dailyLogs.isEmpty ? nil : "\(store.dailyLogs.count)") {
                            GlobalMemoryView()
                        }
                        SettingRow(icon: "terminal", title: "环境变量",
                                   value: store.envVars.isEmpty ? nil : "\(store.envVars.count)", showsDivider: false) {
                            EnvVarsView()
                        }
                    }

                    // 其余：检查更新 / 本机能力 / 日志。
                    SettingsCard {
                        SettingRow(icon: "arrow.down.circle", title: L("update")) {
                            UpdateView()
                        }
                        SettingRow(icon: "iphone", title: L("device_caps"),
                                   value: store.deviceCapabilities.contains { $0.enabled } ? nil : "全部关") {
                            DeviceCapabilitiesView()
                        }
                        SettingRow(icon: "doc.text", title: L("log"), showsDivider: false) {
                            LogView()
                        }
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 16)
            }
            .background(Palette.grouped)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// 白底大圆角分组卡片（r28，原版设置页的卡片样式）：行之间细分隔线，
/// 分隔线从标题 x 处起（不穿过图标）。
private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 28))
    }
}

private struct SettingRow<Destination: View>: View {
    enum Accessory { case chevron, upDownChevrons }

    let icon: String
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var accessory: Accessory = .chevron
    var showsDivider: Bool = true
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 17))
                            .foregroundStyle(Palette.ink)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let value {
                        Text(value)
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)
                    }
                    Group {
                        switch accessory {
                        case .chevron:
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                        case .upDownChevrons:
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                if showsDivider {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// 日志页（关于只留日志，用户定的）：读 LogStore 的真实记录。
struct LogView: View {
    @State private var entries: [LogStore.Entry] = []

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView("暂无日志", systemImage: "doc.text",
                                       description: Text("应用运行日志会记在这里。"))
            } else {
                List(entries) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(e.tag).font(.caption.weight(.semibold))
                            Spacer()
                            Text(e.time, format: .dateTime.hour().minute().second())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(e.message).font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("日志")
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("清空") { LogStore.clear(); entries = [] }
                }
            }
        }
        .task { entries = LogStore.entries() }
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
        .padding(.vertical, 4)
    }

    private var hasCred: Bool {
        !(KeychainHelper.key(ref: "connector-\(connector.id)") ?? "").isEmpty
    }

    private var placeholder: String {
        switch connector.id {
        case "feishu": return "App ID:App Secret（冒号隔开）"
        case "dingtalk": return "AppKey:AppSecret（冒号隔开；要发钉钉消息再加第三段 AgentId）"
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

