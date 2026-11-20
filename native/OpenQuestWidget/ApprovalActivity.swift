import ActivityKit

// MARK: - 锁屏审批 LiveActivity 的属性。
// 这个文件同时编进主 App 和 OpenQuestWidget 两个 target（project.yml 里
// 主 target 的 sources 也列了它），两边用同一份定义，不靠 App Groups 传数据
// （免费个人签名用不了 App Groups）：审批内容随 Activity 本身携带。

struct ApprovalAttributes: ActivityAttributes {
    /// 哪个会话的审批（UUID 字符串）。
    var convId: String
    /// 要做的动作（等宽字体显示在锁屏上）。
    var action: String
    /// 影响说明，可空。
    var impact: String
    /// low / medium / high。
    var risk: String

    struct ContentState: Codable, Hashable {
        var answered: Bool = false
    }
}
