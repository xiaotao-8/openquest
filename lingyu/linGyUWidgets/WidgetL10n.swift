import Foundation

/// The widget extension's own `L()`. The main app's `L10n.swift` is not
/// part of this target, so the extension carries the small table it
/// needs itself. The language comes from the shared App Group snapshot
/// (mirrored there by the app's snapshot writer); the fallback is
/// always the Chinese literal, exactly like the app's `L()`.
///
/// Keep this table in sync with `l10n-additions.swift`: every key here
/// that is not already in the app's `L10n.swift` is listed there for
/// the coordinator to merge, so the two tables never drift apart.
func L(_ zh: String, _ args: CVarArg...) -> String {
    let format = WidgetL10n.string(for: zh)
    guard !args.isEmpty else { return format }
    return String(format: format, arguments: args)
}

enum WidgetL10n {
    static var language: String {
        UserDefaults(suiteName: WidgetSnapshotStore.suiteName)?
            .string(forKey: WidgetSnapshotStore.languageKey) ?? "zh"
    }

    static func string(for zh: String) -> String {
        if language == "en" { return en[zh] ?? zh }
        return zh
    }

    static let en: [String: String] = [
        "智能体": "Agents",
        "需要你确认": "Needs your confirmation",
        "进行中": "In progress",
        "就绪": "Ready",
        "还没有智能体": "No agents yet",
        "在 Codync 里新建第一个智能体。": "Create your first agent in Codync.",
        "连接一台电脑": "Connect a computer",
        "查看": "View",
        "小工具": "Widgets",
        "还没有小工具": "No mini-apps yet",
        "描述一个来创建": "Describe one to create",
        "新建会话": "New conversation",
        "和主智能体开始一段新对话": "Start a new conversation with your lead agent",
        "打开小工具": "Open mini-app",
        "未读": "Unread",
        "静音": "Mute",
        "取消静音": "Unmute",
        "挂断": "End call",
        "通话中": "On a call",
        "通话": "Call",
        "审批": "Approval",
        "已完成": "Done",
        "失败": "Failed",
        "发送中": "Sending",
        "等待电脑": "Waiting for computer",
        "一切正常": "All good",
        "%d 个请求等你确认": "%d requests waiting for you",
        "%d 个在干活": "%d working",
        "%d 个智能体": "%d bots",
        "个智能体": "agents",
    ]
}
