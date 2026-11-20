import Foundation

/// 智能体可调用的工具（统一协议，任何 OpenAI 兼容模型都能用，不绑厂商）。
/// 目前内置：调用用户服务器执行命令。后续连接工具（飞书/钉钉等）按同一协议加。
enum AgentTools {
    static let serverCommandName = "run_server_command"

    static let browseServerName = "browse_on_server"
    static let askUserName = "ask_user"
    static let approvalName = "request_approval"
    static let fetchName = "fetch_webpage"
    static let spawnSubagentName = "spawn_subagent"

    /// 给模型看的工具定义（OpenAI tools 格式）。
    /// capabilities 是已开启的本机能力 id：只有开着的能力才进工具表，
    /// 没开的模型看都看不到（默认全关）。
    static func definitions(capabilities: Set<String> = []) -> [[String: Any]] {
        var defs: [[String: Any]] = [
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
                    "description": "需要用户做选择、或需要用户拍板确认时，必须调用本工具弹提问卡（问题+2到4个选项），不要在正文里罗列选项让用户打字回答。等用户点选后答案会给你。开放式问题（没有明确选项）才直接在回复里问。问题和每个选项的 label 都要短，各不超过 12 个字。timeoutMinutes 是倒计时（1/2/5/10/30/60，0=不限，默认 5），超时只给建议、不自动执行；recommendedId 填你最推荐的那个选项 id；一次问多个问题时把后面的题放 questions 里。",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "question": ["type": "string", "description": "要问用户的问题，一句话，不超过 12 个字"],
                            "options": [
                                "type": "array",
                                "description": "2到4个选项，每个含 id、label（短标签，不超过 12 个字）、detail（一行说明）",
                                "items": ["type": "object"],
                            ],
                            "multiSelect": ["type": "boolean", "description": "是否可多选，默认 false"],
                            "timeoutMinutes": ["type": "integer", "description": "倒计时分钟数：1/2/5/10/30/60，0=不限，默认 5"],
                            "recommendedId": ["type": "string", "description": "最推荐的选项 id，卡片上打推荐角标"],
                            "questions": ["type": "array", "description": "后面的问题（同结构），卡片上可翻页作答"],
                        ],
                        "required": ["question", "options"],
                    ],
                ],
            ],
            [
                "type": "function",
                "function": [
                    "name": approvalName,
                    "description": "要做敏感操作（启用连接器、给权限、删东西、花钱）前调用：弹审批卡，用户批准才执行，拒绝就停手。action 写精确的动作（如 rm /path/file），impact 写影响和风险，risk 写 low/medium/high。",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "action": ["type": "string", "description": "要做的精确操作"],
                            "impact": ["type": "string", "description": "影响和风险，一行说明"],
                            "risk": ["type": "string", "description": "风险等级：low / medium / high"],
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
            [
                "type": "function",
                "function": [
                    "name": spawnSubagentName,
                    "description": "把一个子任务派给另一个智能体：它另起一轮独立跑完，把结果正文带回来给你。agent 填对方的名字或 id，task 写清楚要做的事。子智能体不能再派子智能体。",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "agent": ["type": "string", "description": "子智能体的名字或 id"],
                            "task": ["type": "string", "description": "交给它做的事，写清楚"],
                        ],
                        "required": ["agent", "task"],
                    ],
                ],
            ],
        ]
        // 本机能力：只把已开启的能力放进工具表。
        if capabilities.contains("calendar") {
            defs.append([
                "type": "function",
                "function": [
                    "name": "device_calendar",
                    "description": "在用户手机日历里新建一个日程。start 用 ISO8601 时间（如 2026-11-21T09:00:00+08:00）。",
                    "parameters": ["type": "object", "properties": [
                        "title": ["type": "string", "description": "日程标题"],
                        "start": ["type": "string", "description": "开始时间，ISO8601"],
                        "durationMinutes": ["type": "integer", "description": "时长（分钟），默认 60"],
                        "notes": ["type": "string", "description": "备注"],
                    ], "required": ["title", "start"]],
                ],
            ])
        }
        if capabilities.contains("reminders") {
            defs.append([
                "type": "function",
                "function": [
                    "name": "device_reminder",
                    "description": "在用户手机提醒事项里新建一条提醒。",
                    "parameters": ["type": "object", "properties": [
                        "title": ["type": "string", "description": "提醒内容"],
                        "notes": ["type": "string", "description": "备注"],
                    ], "required": ["title"]],
                ],
            ])
        }
        if capabilities.contains("photos") {
            defs.append([
                "type": "function",
                "function": [
                    "name": "device_photos",
                    "description": "看用户相册里最近照片的数量和拍摄时间（只读信息，不拿原图）。",
                    "parameters": ["type": "object", "properties": [:]],
                ],
            ])
        }
        if capabilities.contains("clipboard") {
            defs.append([
                "type": "function",
                "function": [
                    "name": "device_clipboard",
                    "description": "读写用户手机剪贴板：action=read 读文字，action=write 写文字（需 text）。",
                    "parameters": ["type": "object", "properties": [
                        "action": ["type": "string", "description": "read / write"],
                        "text": ["type": "string", "description": "write 时要写入的文字"],
                    ], "required": ["action"]],
                ],
            ])
        }
        if capabilities.contains("location") {
            defs.append([
                "type": "function",
                "function": [
                    "name": "device_location",
                    "description": "读一次用户当前位置（经纬度）。",
                    "parameters": ["type": "object", "properties": [:]],
                ],
            ])
        }
        if capabilities.contains("contacts") {
            defs.append([
                "type": "function",
                "function": [
                    "name": "device_contacts",
                    "description": "按名字在用户通讯录里查联系人，返回名字和电话。",
                    "parameters": ["type": "object", "properties": [
                        "name": ["type": "string", "description": "要查的名字（部分匹配）"],
                    ], "required": ["name"]],
                ],
            ])
        }
        return defs
    }

    /// 执行一次工具调用，返回给模型看的文本结果。
    /// workDir 是智能体的工作文件夹（""=团队工作区）：服务器命令在那个目录里跑。
    static func execute(name: String, argumentsJSON: String,
                        agentId: String, server: ServerConfig,
                        workDir: String = "",
                        onEvent: ((String, Data?) -> Void)? = nil) async -> String {
        switch name {
        case serverCommandName:
            guard let data = argumentsJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let command = obj["command"] as? String, !command.isEmpty
            else { return "参数不对：缺 command" }
            onEvent?("正在服务器上执行命令…", nil)
            do {
                let cmd = workDir.isEmpty ? command
                    : "cd '\(workDir.replacingOccurrences(of: "'", with: "'\\''"))' && \(command)"
                let r = try await ServerClient(config: server).exec(agentId: agentId, command: cmd)
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
            onEvent?("正在用服务器浏览器…", nil)
            do {
                let r = try await ServerClient(config: server)
                    .browserAction(agentId: agentId, action: obj)
                if let b64 = r.screenshotBase64, let d = Data(base64Encoded: b64) {
                    onEvent?("浏览器 · \(r.title)", d)
                }
                return "页面：\(r.title)（\(r.url)）\n正文：\n\(String(r.text.prefix(6000)))"
            } catch {
                return "服务器浏览器操作失败：\(error.localizedDescription)"
            }
        case "device_calendar":
            guard let data = argumentsJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let title = obj["title"] as? String, !title.isEmpty,
                  let start = obj["start"] as? String, !start.isEmpty
            else { return "参数不对：device_calendar 要 title 和 start" }
            onEvent?("正在加日程…", nil)
            return await DeviceTools.addCalendarEvent(
                title: title, startISO: start,
                durationMinutes: (obj["durationMinutes"] as? Int) ?? 60,
                notes: (obj["notes"] as? String) ?? "")
        case "device_reminder":
            guard let data = argumentsJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let title = obj["title"] as? String, !title.isEmpty
            else { return "参数不对：device_reminder 要 title" }
            onEvent?("正在加提醒…", nil)
            return await DeviceTools.addReminder(
                title: title, notes: (obj["notes"] as? String) ?? "")
        case "device_photos":
            onEvent?("正在看相册…", nil)
            return await DeviceTools.recentPhotos()
        case "device_clipboard":
            guard let data = argumentsJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let action = obj["action"] as? String
            else { return "参数不对：device_clipboard 要 action" }
            if action == "write" {
                let text = (obj["text"] as? String) ?? ""
                return await DeviceTools.writeClipboard(text)
            }
            return await DeviceTools.readClipboard()
        case "device_location":
            onEvent?("正在取位置…", nil)
            return await DeviceTools.currentLocation()
        case "device_contacts":
            guard let data = argumentsJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = obj["name"] as? String, !name.isEmpty
            else { return "参数不对：device_contacts 要 name" }
            onEvent?("正在查通讯录…", nil)
            return await DeviceTools.searchContacts(name: name)
        case spawnSubagentName:
            return "子智能体没配好：这一轮不能派活"
        case fetchName:
            guard let data = argumentsJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let raw = obj["url"] as? String, let url = URL(string: raw)
            else { return "参数不对：缺 url" }
            onEvent?("正在抓取网页…", nil)
            do {
                var req = URLRequest(url: url)
                req.timeoutInterval = 20
                req.setValue("Mozilla/5.0 (iPhone) Safari", forHTTPHeaderField: "User-Agent")
                let (data, _) = try await Net.session.data(for: req)
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
