import SwiftUI
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
    @State private var showingLog = false
    @State private var showingAnalyticsInfo = false
    @State private var showingStartOverDialog = false
    @State private var notificationStatus = ""
    @State private var iconBadge = false
    @State private var shareAnalytics = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text(L("设置"))
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Palette.text)
                    .padding(.top, 8)
                appearanceSection
                languageSection
                thinkingSection
                shortcutSection
                notificationsSection
                analyticsSection
                aboutSection
                startOverSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Palette.background)
        .codyncSheet(isPresented: $showingLog) {
            LogView()
        }
        .codyncSheet(isPresented: $showingAnalyticsInfo) {
            AnalyticsInfoView()
        }
        .codyncDialog(
            isPresented: $showingStartOverDialog,
            title: L("重新开始？"),
            message: L("登出所有账号、忘掉这部手机上的所有电脑，然后重新显示欢迎页。你电脑上的智能体与聊天不受影响，重新配对即可继续使用。"),
            actions: [
                CodyncDialogAction(title: L("取消")) {},
                CodyncDialogAction(title: L("重新开始"), isDestructive: true) {
                    store.connector.forgetComputer()
                    store.showingWelcome = true
                },
            ]
        )
        .onAppear {
            loadNotificationStatus()
            iconBadge = UserDefaults.standard.bool(forKey: "cn.lingyu.iconBadge")
            shareAnalytics = UserDefaults.standard.object(forKey: "cn.lingyu.shareAnalytics") as? Bool ?? true
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        CardSection(title: L("外观")) {
            ForEach([("system", L("跟随系统")), ("light", L("浅色")), ("dark", L("深色"))], id: \.0) { item in
                CardRow {
                    Button {
                        store.appearance = item.0
                    } label: {
                        HStack {
                            Text(item.1)
                                .foregroundStyle(Palette.text)
                            Spacer()
                            if store.appearance == item.0 {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Palette.text)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                if item.0 != "dark" {
                    Hairline()
                }
            }
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        CardSection(title: L("语言"), footer: L("更多语言后续推出。")) {
            ForEach(languageOptions, id: \.code) { option in
                CardRow {
                    Button {
                        if option.enabled {
                            store.setLanguage(option.code)
                        }
                    } label: {
                        HStack {
                            Text(option.title)
                                .foregroundStyle(option.enabled ? Palette.text : Palette.tertiary)
                            Spacer()
                            if !option.enabled {
                                Text(L("即将推出"))
                                    .font(.caption)
                                    .foregroundStyle(Palette.tertiary)
                            } else if store.language == option.code {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Palette.text)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!option.enabled)
                }
                if option.code != languageOptions.last?.code {
                    Hairline()
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
        CardSection(title: L("思考详情")) {
            CardRow {
                Toggle(L("显示思考过程"), isOn: $store.showThinkingDetails)
                    .toggleStyle(.codync)
            }
        }
    }

    // MARK: - Shortcut lead bot

    private var shortcutSection: some View {
        CardSection(title: L("快捷指令主智能体")) {
            let bots = store.connector.mirror.bots.filter { !$0.isGroup }
            if bots.isEmpty {
                CardRow {
                    Text(L("还没有智能体。"))
                        .foregroundStyle(Palette.secondary)
                }
            } else {
                ForEach(bots) { bot in
                    CardRow {
                        Button {
                            Task {
                                try? await store.connector.api?.setLead(botId: bot.id)
                            }
                        } label: {
                            HStack {
                                AvatarView(bot: bot, size: 28)
                                Text(bot.name)
                                    .foregroundStyle(Palette.text)
                                Spacer()
                                if bot.lead {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Palette.text)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if bot.id != bots.last?.id {
                        Hairline()
                    }
                }
            }
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        CardSection(title: L("通知")) {
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
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.tertiary)
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
        CardSection(title: L("分析"), footer: L("只统计功能使用情况，不含消息、代码与文件内容。")) {
            CardRow {
                HStack {
                    Toggle(L("分享使用分析"), isOn: Binding(
                        get: { shareAnalytics },
                        set: {
                            shareAnalytics = $0
                            UserDefaults.standard.set($0, forKey: "cn.lingyu.shareAnalytics")
                        }
                    ))
                    .toggleStyle(.codync)
                    Button {
                        showingAnalyticsInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Palette.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("分析说明"))
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
        Button {
            showingStartOverDialog = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundStyle(Palette.danger)
                Text(L("重新开始"))
                    .foregroundStyle(Palette.danger)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
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
