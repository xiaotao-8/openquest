import SwiftUI
import PhotosUI
import UserNotifications

/// The app log (About → Log only). Timestamped lines, capped at 200,
/// persisted in UserDefaults so the startup log survives a relaunch.
enum LogStore {
    private static let key = "cn.lingyu.log.v1"
    private static let cap = 200

    static var entries: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func record(_ message: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm:ss"
        var lines = entries
        lines.append("\(formatter.string(from: Date())) \(message)")
        if lines.count > cap {
            lines.removeFirst(lines.count - cap)
        }
        UserDefaults.standard.set(lines, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Settings (§1.5): Codync's settings page with the brand rows removed.
/// Every row is real — a working control or a working destination.
/// About keeps only the log; no version row, no rating, no report link.
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var avatarStore = AvatarStore.shared
    @State private var myName = UserDefaults.standard.string(forKey: "cn.lingyu.myName") ?? ""
    @AppStorage("cn.lingyu.showAgentLogos") private var showAgentLogos = true
    @State private var shortcutLead = UserDefaults.standard.string(forKey: "cn.lingyu.shortcutLead") ?? "automatic"
    @State private var showingPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showingLog = false
    @State private var showingAnalyticsInfo = false
    @State private var showingStartOverDialog = false
    @State private var showingDeleteDialog = false
    @State private var showingBypassDialog = false
    @State private var showingSoul = false
    @State private var showingMemory = false
    @State private var showingIdentity = false
    @State private var showingDataControls = false
    @State private var showingVault = false
    @State private var showingNetwork = false
    @State private var showingVoice = false
    @State private var didHandlePreview = false
    @State private var notificationStatus = ""
    @State private var iconBadge = false
    @State private var shareAnalytics = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text(L("设置"))
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Palette.text)
                    .padding(.top, 20)
                profileSection
                accountSection
                identitySection
                appearanceSection
                languageSection
                thinkingSection
                voiceSection
                permissionsSection
                dataSection
                shortcutSection
                notificationsSection
                analyticsSection
                aboutSection
                startOverSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Palette.background)
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let image = await AvatarStore.load(item) {
                    avatarStore.save(image, for: AvatarStore.meOwnerId)
                }
            }
        }
        .codyncSheet(isPresented: $showingLog) {
            LogView()
        }
        .codyncSheet(isPresented: $store.showingSignIn) {
            SignInSheet()
        }
        .codyncSheet(isPresented: $showingAnalyticsInfo) {
            AnalyticsInfoView()
        }
        .codyncSheet(isPresented: $showingSoul) {
            NavigationStack { SoulView() }
        }
        .codyncSheet(isPresented: $showingMemory) {
            NavigationStack { MemoryView() }
        }
        .codyncSheet(isPresented: $showingIdentity) {
            NavigationStack { IdentityView() }
        }
        .codyncSheet(isPresented: $showingDataControls) {
            NavigationStack { DataControlsView() }
        }
        .codyncSheet(isPresented: $showingVault) {
            NavigationStack { CredentialVaultView() }
        }
        .codyncSheet(isPresented: $showingNetwork) {
            NavigationStack { NetworkProtocolsView() }
        }
        .codyncSheet(isPresented: $showingVoice) {
            NavigationStack { VoiceSettingsView() }
        }
        .codyncDialog(
            isPresented: $showingDeleteDialog,
            title: L("删除账号？"),
            message: L("删除账号后，账号会被永久删除，云电脑列表会回到未登录时的显示。这部手机上已配对的电脑不受影响。"),
            actions: [
                CodyncDialogAction(title: L("取消")) {},
                CodyncDialogAction(title: L("删除账号"), isDestructive: true) {
                    Task { @MainActor in
                        do {
                            try await store.account.deleteUser()
                            store.clearAccountCloud()
                        } catch {
                            store.account.errorMessage = L("删除失败，请重试。")
                        }
                    }
                },
            ]
        )
        .codyncDialog(
            isPresented: $showingStartOverDialog,
            title: L("重新开始？"),
            message: L("登出所有账号、忘掉这部手机上的所有电脑，然后重新显示欢迎页。你电脑上的智能体与聊天不受影响，重新配对即可继续使用。"),
            actions: [
                CodyncDialogAction(title: L("取消")) {},
                CodyncDialogAction(title: L("重新开始"), isDestructive: true) {
                    Task { await store.startOver() }
                },
            ]
        )
        .codyncDialog(
            isPresented: $showingBypassDialog,
            title: L("开启全部跳过审批？"),
            message: L("开启后，智能体无需确认即可运行命令、修改文件和访问网络。只在你完全信任这台电脑上的智能体时开启，随时可以关掉。"),
            actions: [
                CodyncDialogAction(title: L("取消")) {},
                CodyncDialogAction(title: L("开启"), isDestructive: true) {
                    store.bypassAllApprovals = true
                },
            ]
        )
        .onAppear {
            loadNotificationStatus()
            iconBadge = UserDefaults.standard.bool(forKey: "cn.lingyu.iconBadge")
            shareAnalytics = UserDefaults.standard.object(forKey: "cn.lingyu.shareAnalytics") as? Bool ?? true
            if !didHandlePreview, case .seeded(let options) = store.previewMode {
                didHandlePreview = true
                if options.soul { showingSoul = true }
                else if options.memory { showingMemory = true }
                else if options.identity { showingIdentity = true }
                else if options.vault { showingVault = true }
                else if options.network { showingNetwork = true }
                else if options.voice { showingVoice = true }
                else if options.dataControls { showingDataControls = true }
            }
        }
    }

    // MARK: - My profile

    /// The user's own name and photo. Tap the avatar to pick a photo;
    /// the photo is stored locally and shown wherever the user's avatar
    /// appears. No name or photo is pre-filled.
    private var profileSection: some View {
        CardSection(title: L("我的资料")) {
            CardRow {
                HStack(spacing: 14) {
                    Button {
                        showingPhotoPicker = true
                    } label: {
                        AvatarView(name: displayName, color: "blue", shape: "blob", size: 64, ownerId: AvatarStore.meOwnerId)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("选择照片"))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("你的名字"))
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondary)
                        TextField(L("你的名字"), text: $myName)
                            .font(.body)
                            .foregroundStyle(Palette.text)
                            .onChange(of: myName) { _, new in
                                UserDefaults.standard.set(new, forKey: "cn.lingyu.myName")
                            }
                    }
                }
            }
            if avatarStore.hasPhoto(for: AvatarStore.meOwnerId) {
                Hairline()
                CardRow {
                    Button(L("移除照片"), role: .destructive) {
                        avatarStore.remove(for: AvatarStore.meOwnerId)
                    }
                    .foregroundStyle(Palette.danger)
                }
            }
        }
    }

    private var displayName: String {
        let trimmed = myName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L("我") : trimmed
    }

    // MARK: - Account

    /// The account sign-in. Signed out: one button opens the sign-in sheet.
    /// Signed in: the account's email (and avatar, when the account has an
    /// https one) with sign-out and delete-account actions. Signing out
    /// keeps the local pairing and device key; deleting the account only
    /// clears the account's own data on this phone.
    private var accountSection: some View {
        CardSection(title: L("账号")) {
            if store.account.isSignedIn {
                CardRow {
                    HStack(spacing: 14) {
                        accountAvatar
                        Text(store.account.email ?? "")
                            .font(.body)
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Hairline()
                CardRow {
                    Button(L("登出"), role: .destructive) {
                        Task { @MainActor in await store.signOutAccount() }
                    }
                    .foregroundStyle(Palette.danger)
                }
                Hairline()
                CardRow {
                    Button(L("删除账号"), role: .destructive) {
                        showingDeleteDialog = true
                    }
                    .foregroundStyle(Palette.danger)
                }
            } else {
                CardRow {
                    Button(L("登录账号")) {
                        store.showingSignIn = true
                    }
                    .foregroundStyle(Palette.text)
                }
            }
            if let message = store.account.errorMessage, store.account.isSignedIn {
                Hairline()
                CardRow {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
            }
        }
    }

    private var accountAvatar: some View {
        Group {
            if let url = store.account.avatarURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Palette.surface
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())
            } else {
                ZStack {
                    Circle().fill(Palette.surface)
                    Text(String((store.account.email ?? "?").prefix(1)).uppercased())
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Palette.secondary)
                }
                .frame(width: 64, height: 64)
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        CardSection(title: L("外观"), footer: L("只改这部设备上的外观。")) {
            CardRow {
                ValueRow(label: L("主题")) {
                    ChoicePicker(selection: $store.appearance, options: [
                        ("system", L("跟随系统")), ("light", L("浅色")), ("dark", L("深色")),
                    ])
                }
            }
            Hairline()
            CardRow {
                SwitchRow(label: L("显示智能体图标"), detail: L("智能体用多个不同后端时，在每个智能体旁标出它的图标。"), isOn: $showAgentLogos)
            }
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        CardSection(title: L("语言"), footer: L("选择这部设备用的语言。不支持的系统语言用英文。")) {
            CardRow {
                ValueRow(label: L("App 语言")) {
                    ChoicePicker(selection: $store.language, options: languageOptions.map { ($0.code, $0.title) },
                                 disabled: Set(languageOptions.filter { !$0.enabled }.map(\.code)))
                }
            }
        }
    }

    private struct LanguageOption {
        var code: String
        var title: String
        var enabled: Bool
    }

    /// Phase 1 ships Chinese and English complete; the other four are a
    /// known gap for Phase 2 and are shown disabled with a reason, never
    /// as if they worked.
    private var languageOptions: [LanguageOption] {
        [
            LanguageOption(code: "zh", title: "中文", enabled: true),
            LanguageOption(code: "en", title: "English", enabled: true),
            LanguageOption(code: "ja", title: "日本語", enabled: false),
            LanguageOption(code: "ko", title: "한국어", enabled: false),
            LanguageOption(code: "es", title: "Español", enabled: false),
            LanguageOption(code: "fr", title: "Français", enabled: false),
        ]
    }

    // MARK: - Thinking details

    private var thinkingSection: some View {
        CardSection(title: L("聊天"), footer: L("可以在聊天里从智能体的状态展开它的思考和步骤。只改这部设备。")) {
            CardRow {
                Toggle(L("显示思考过程"), isOn: $store.showThinkingDetails)
                    .toggleStyle(.codync)
            }
        }
    }

    // MARK: - Permissions

    /// Skip-all-approvals sits at the top of Permissions, off by default.
    /// Turning it on asks once for an explicit risk confirmation; turning
    /// it off restores per-item approval at once. Ask cards (questions)
    /// are never covered by this switch.
    private var permissionsSection: some View {
        CardSection(title: L("权限"), footer: L("开启后，智能体执行操作不再逐项请示你；提问卡不受影响，问题还是会问你。")) {
            CardRow {
                SwitchRow(label: L("全部跳过审批"), detail: L("智能体无需确认即可运行命令、修改文件和访问网络。"), isOn: Binding(
                    get: { store.bypassAllApprovals },
                    set: { newValue in
                        if newValue {
                            showingBypassDialog = true
                        } else {
                            store.bypassAllApprovals = false
                        }
                    }
                ))
            }
            Hairline()
            CardRow {
                Button {
                    showingNetwork = true
                } label: {
                    HStack {
                        Text(L("网络协议"))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Identity (Soul / Memory / Identity)

    /// The three-file user model: Soul (top-priority instructions),
    /// Memory (what the agent remembers), Identity (who the agent is).
    private var identitySection: some View {
        CardSection(title: L("智能体"), footer: L("Soul 是最高优先级的指令，智能体必须完全服从；Memory 是它记住的关于你的事；Identity 是它自己是谁。")) {
            CardRow {
                Button {
                    showingSoul = true
                } label: {
                    HStack {
                        Text(L("Soul"))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            Hairline()
            CardRow {
                Button {
                    showingMemory = true
                } label: {
                    HStack {
                        Text(L("Memory"))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            Hairline()
            CardRow {
                Button {
                    showingIdentity = true
                } label: {
                    HStack {
                        Text(L("Identity"))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Voice

    /// Voice service: the call engine (on-device only while the
    /// computer's credential store is locked), the reading voice, and
    /// whether replies are read aloud.
    private var voiceSection: some View {
        CardSection(title: L("语音"), footer: L("通话与按住说话都在这台设备上识别与朗读，不走电脑端。")) {
            CardRow {
                Button {
                    showingVoice = true
                } label: {
                    HStack {
                        Text(L("语音服务"))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Text(L("设备语音"))
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Data & credentials

    private var dataSection: some View {
        CardSection(title: L("数据与凭证")) {
            CardRow {
                Button {
                    showingDataControls = true
                } label: {
                    HStack {
                        Text(L("数据控制"))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            Hairline()
            CardRow {
                Button {
                    showingVault = true
                } label: {
                    HStack {
                        Text(L("安全凭证库"))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Shortcut lead bot

    /// Only when there is more than one bot to pick from.
    private var shortcutSection: some View {
        let bots = store.connector.mirror.bots.filter { !$0.isGroup }
        return Group {
            if bots.count > 1 {
                CardSection(title: L("快捷指令"), footer: L("Siri、操作按钮和无智能体打开的实时模式都会叫这位主智能体。自动会叫你列表里第一台电脑的主智能体。")) {
                    CardRow {
                        ValueRow(label: L("主智能体")) {
                            ChoicePicker(selection: Binding(
                                get: { shortcutLead },
                                set: { newValue in
                                    shortcutLead = newValue
                                    UserDefaults.standard.set(newValue, forKey: "cn.lingyu.shortcutLead")
                                    if newValue != "automatic" {
                                        Task {
                                            try? await store.connector.api?.setLead(botId: newValue)
                                        }
                                    }
                                }
                            ), options: [("automatic", L("自动"))] + bots.map { ($0.id, "\($0.name) · \(store.connector.computer?.name ?? "")") })
                        }
                    }
                }
            }
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        CardSection(title: L("通知"), footer: L("收到结果摘要、需要你确认的请求或失败提醒。通知预览跟随你的 iOS 设置。")) {
            CardRow {
                Button {
                    openNotificationSettings()
                } label: {
                    HStack {
                        Text(L("通知"))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Text(notificationStatus)
                            .foregroundStyle(Palette.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            Hairline()
            CardRow {
                Toggle(L("App 图标未读数"), isOn: Binding(
                    get: { iconBadge },
                    set: {
                        iconBadge = $0
                        UserDefaults.standard.set($0, forKey: "cn.lingyu.iconBadge")
                        if !$0 {
                            UIApplication.shared.applicationIconBadgeNumber = 0
                        }
                    }
                ))
                .toggleStyle(.codync)
            }
        }
    }

    private func loadNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional:
                    notificationStatus = L("已开启")
                case .denied:
                    notificationStatus = L("已关闭")
                case .notDetermined:
                    notificationStatus = L("未设置")
                default:
                    notificationStatus = L("未设置")
                }
            }
        }
    }

    private func openNotificationSettings() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                if settings.authorizationStatus == .notDetermined {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
                        loadNotificationStatus()
                    }
                } else if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    // MARK: - Analytics

    private var analyticsSection: some View {
        CardSection(footer: L("只统计功能使用情况，不含消息、代码与文件内容。")) {
            CardRow {
                HStack(spacing: 4) {
                    Text(L("分享使用分析"))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Button {
                        showingAnalyticsInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.iconButton)
                    .accessibilityLabel(L("分析说明"))
                    Toggle(isOn: Binding(
                        get: { shareAnalytics },
                        set: {
                            shareAnalytics = $0
                            UserDefaults.standard.set($0, forKey: "cn.lingyu.shareAnalytics")
                        }
                    )) {
                        EmptyView()
                    }
                    .toggleStyle(.codync)
                }
            }
        }
    }

    // MARK: - About (log only)

    private var aboutSection: some View {
        CardSection(title: L("关于")) {
            CardRow {
                Button {
                    showingLog = true
                } label: {
                    HStack {
                        Text(L("日志"))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Danger zone

    private var startOverSection: some View {
        CardSection {
            CardRow {
                Button {
                    showingStartOverDialog = true
                } label: {
                    Label(L("重新开始"), systemImage: "arrow.counterclockwise")
                        .foregroundStyle(Palette.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct AnalyticsInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("使用分析")) {
                dismiss()
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(L("开启后，App 会统计哪些功能被用到、以及哪里出错，以便改进。统计不含你的消息、代码、文件内容，也不含任何账号信息。关闭后不再统计。"))
                    .font(.body)
                    .foregroundStyle(Palette.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(Palette.background)
    }
}

struct LogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [String] = LogStore.entries
    @State private var showingClearDialog = false

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("日志"), trailing: AnyView(
                Button(L("清空")) {
                    showingClearDialog = true
                }
                .font(.subheadline)
                .foregroundStyle(Palette.danger)
            )) {
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if entries.isEmpty {
                        Text(L("还没有日志。"))
                            .font(.body)
                            .foregroundStyle(Palette.secondary)
                            .padding(.top, 24)
                    } else {
                        ForEach(entries, id: \.self) { line in
                            Text(line)
                                .font(.caption.monospaced())
                                .foregroundStyle(Palette.text)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(Palette.background)
        .codyncDialog(
            isPresented: $showingClearDialog,
            title: L("清空日志？"),
            message: L("所有日志行都会被删除。"),
            actions: [
                CodyncDialogAction(title: L("取消")) {},
                CodyncDialogAction(title: L("清空"), isDestructive: true) {
                    LogStore.clear()
                    entries = []
                },
            ]
        )
    }
}
