import Foundation

/// 智能体可调用的工具（统一协议，任何 OpenAI 兼容模型都能用，不绑厂商）。
/// 目前内置：调用用户服务器执行命令。后续连接工具（飞书/钉钉等）按同一协议加。
enum AgentTools {
    static let serverCommandName = "run_server_command"

    static let browseServerName = "browse_on_server"
    static let askUserName = "ask_user"
    static let approvalName = "request_approval"
    static let fetchName = "fetch_webpage"

    /// 给模型看的工具定义（OpenAI tools 格式）。
    static var definitions: [[String: Any]] {
        [
            [
                "type": "function",
                "function": [
                    "name": serverCommandName,
                    "description": "在用户自己的服务器上执行一条 shell 命令，返回标准输出、错误输出和退出码。命令在该智能体自己的工作目录里运行。",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "command": ["type": "string", "description": "要执行的命令"]
                        ],
                        "required": ["command"],
                    ],
                ],
            ],
            [
                "type": "function",
                "function": [
                    "name": browseServerName,
                    "description": "操作服务器上的真实浏览器（跟 Muse 的浏览器同规格）：一步一个动作，每步返回页面标题、正文和截图。action=navigate 需 url；click 需 x、y（0到1的相对坐标，按截图位置点）；type 需 text（输入到当前焦点）；scroll 需 dy；read 只读当前页；screenshot 只截图。登录状态保存在服务器上。遇到验证码等验证步骤停下来，让用户自己操作。",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "action": ["type": "string", "description": "navigate / click / type / scroll / read / screenshot"],
                            "url": ["type": "string", "description": "navigate 时的网址"],
                            "x": ["type": "number", "description": "click 时的横坐标，0到1"],
                            "y": ["type": "number", "description": "click 时的纵坐标，0到1"],
                            "text": ["type": "string", "description": "type 时输入的文字"],
                            "dy": ["type": "number", "description": "scroll 时的滚动距离"],
                        ],
                        "required": ["action"],
                    ],
                ],
            ],
            [
                "type": "function",
                "function": [
                    "name": askUserName,
                    "description": "需要用户做选择、或需要用户拍板确认时，必须调用本工具弹提问卡（问题+2到4个选项），不要在正文里罗列选项让用户打字回答。等用户点选后答案会给你。开放式问题（没有明确选项）才直接在回复里问。",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "question": ["type": "string", "description": "要问用户的问题，一句话"],
                            "options": [
                                "type": "array",
                                "description": "2到4个选项，每个含 id、label（短标签）、detail（一行说明）",
                                "items": ["type": "object"],
                            ],
                            "multiSelect": ["type": "boolean", "description": "是否可多选，默认 false"],
                        ],
                        "required": ["question", "options"],
                    ],
                ],
            ],
            [
                "type": "function",
                "function": [
                    "name": approvalName,
                    "description": "要做敏感操作（启用连接器、给权限、删东西、花钱）前调用：弹审批卡，用户批准才执行，拒绝就停手。",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "action": ["type": "string", "description": "要做的操作"],
                            "impact": ["type": "string", "description": "影响和风险，一行说明"],
                        ],
                        "required": ["action", "impact"],
                    ],
                ],
            ],
            [
                "type": "function",
                "function": [
                    "name": fetchName,
                    "description": "抓取一个网页的正文文本（给 URL，返回可读内容），用来查资料、看页面。App 里也有内置浏览器可打开页面。",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "url": ["type": "string", "description": "网页地址"]
                        ],
                        "required": ["url"],
                    ],
                ],
            ],
        ]
    }

    /// 执行一次工具调用，返回给模型看的文本结果。
    static func execute(name: String, argumentsJSON: String,
                        agentId: String, server: ServerConfig) async -> String {
        switch name {
        case serverCommandName:
            guard let data = argumentsJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let command = obj["command"] as? String, !command.isEmpty
            else { return "参数不对：缺 command" }
            do {
                let r = try await ServerClient(config: server).exec(agentId: agentId, command: command)
                var out = "退出码 \(r.exitCode)"
                if !r.stdout.isEmpty { out += "\n输出：\n\(r.stdout)" }
                if !r.stderr.isEmpty { out += "\n错误：\n\(r.stderr)" }
                return out
            } catch {
                return "调用服务器失败：\(error.localizedDescription)"
            }
        case browseServerName:
            guard let data = argumentsJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let _ = obj["action"] as? String
            else { return "参数不对：缺 action" }
            do {
                let r = try await ServerClient(config: server)
                    .browserAction(agentId: agentId, action: obj)
                return "页面：\(r.title)（\(r.url)）\n正文：\n\(String(r.text.prefix(6000)))"
            } catch {
                return "服务器浏览器操作失败：\(error.localizedDescription)"
            }
        case fetchName:
            guard let data = argumentsJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let raw = obj["url"] as? String, let url = URL(string: raw)
            else { return "参数不对：缺 url" }
            do {
                var req = URLRequest(url: url)
                req.timeoutInterval = 20
                req.setValue("Mozilla/5.0 (iPhone) Safari", forHTTPHeaderField: "User-Agent")
                let (data, _) = try await URLSession.shared.data(for: req)
                let html = String(data: data, encoding: .utf8) ?? ""
                return Self.htmlToText(html)
            } catch {
                return "抓取失败：\(error.localizedDescription)"
            }
        default:
            return "未知工具 \(name)"
        }
    }

    /// 粗剥 HTML：去 script/style/标签，留正文（截断 6000 字防爆上下文）。
    static func htmlToText(_ html: String) -> String {
        var s = html
        for tag in ["script", "style"] {
            while let r = s.range(of: "<\(tag)", options: .caseInsensitive),
                  let e = s.range(of: "</\(tag)>", options: .caseInsensitive, range: r.lowerBound..<s.endIndex) {
                s.removeSubrange(r.lowerBound..<e.upperBound)
            }
        }
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(s.prefix(6000))
    }
}
