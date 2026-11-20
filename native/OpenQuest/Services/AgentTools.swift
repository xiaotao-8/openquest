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

    /// 聊天页搭的桥：AppStore 没有共享单例（@StateObject 只在 App 入口），
    /// minis-config 读写要 store，AgentRunner 又不传——聊天页每轮开始前把
    /// 自己的 store / 智能体名放在这里（weak，不留住），execute 用完即取。
    /// 更干净的做法是把 store 穿进 AgentRunner（不在本次归属内，见汇报遗留）。
    static weak var sharedStore: AppStore?
    static var sharedAgentName: String = ""

    /// 派活桥：子智能体派活要回到聊天页的 spawnSubagent 闭包（另起一轮
    /// GuardedTurn），AgentRunner 直传的 onSpawn 只在当轮有效；审批卡批了
    /// 之后重跑走 execute → run()，靠这座桥才能真派活，不然只会回“没配好”。
    /// 聊天页每轮 replyFrom 里搭好（与 sharedStore 同一位置）。
    static var sharedSpawn: ((String, String) async -> String)?

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
                    "description": "需要用户做选择、或需要用户拍板确认时，必须调用本工具弹提问卡（问题+2到4个选项），不要在正文里罗列选项让用户打字回答。等用户点选后答案会给你。开放式问题（没有明确选项）才直接在回复里问。问题是一句话；每个选项的 label 都要短，不超过 12 个字；header 是问题旁边的小标签，不超过 12 个字。选项按推荐程度从好到差排，最好的放第一个，卡片会自动给第一个打推荐角标。timeoutMinutes 是倒计时（1/2/5/10/30/60，0=不限，默认 5），超时只给建议、不自动执行；一次问多个问题时把后面的题放 questions 里。",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "question": ["type": "string", "description": "要问用户的问题，一句话"],
                            "header": ["type": "string", "description": "问题旁边的小标签，不超过 12 个字，可不填"],
                            "options": [
                                "type": "array",
                                "description": "2到4个选项，按推荐程度从好到差排，每个含 id、label（短标签，不超过 12 个字）、detail（一行说明）",
                                "items": ["type": "object"],
                            ],
                            "multiSelect": ["type": "boolean", "description": "是否可多选，默认 false"],
                            "timeoutMinutes": ["type": "integer", "description": "倒计时分钟数：1/2/5/10/30/60，0=不限，默认 5"],
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
        // minis-config：只在总开关开时进工具表（关了模型看都看不到）。
        if MinisConfig.isEnabled {
            defs += MinisConfig.toolDefinitions()
        }
        return defs
    }

    /// 工具调用行事件（Minis 式：绿勾 + 调用文字 + 耗时）。
    /// AgentRunner 不在本阶段改动范围内，所以开始/完成信号走现成的
    /// onEvent 文本通道：带控制前缀的文本只给聊天页解析，绝不进界面
    /// 或发给模型；普通进度文本（浏览器截图标题等）原样通过。
    struct ToolCallEvent {
        enum Kind { case start, done }
        var kind: Kind
        var callId: String
        var name: String
        var label: String
        var seconds: TimeInterval? = nil
        var ok: Bool = true

        /// 控制前缀（\u{1} 正常文本里不会出现）；字段用 \t 分隔，
        /// label 里已把空白压成单空格，不含 \t。
        static let marker = "\u{1}oq-tool\u{1}"

        static func encodeStart(callId: String, name: String, label: String) -> String {
            [marker, "start", callId, name, label].joined(separator: "\t")
        }

        static func encodeDone(callId: String, name: String, label: String,
                               seconds: TimeInterval, ok: Bool) -> String {
            [marker, "done", callId, name, label,
             String(format: "%.3f", seconds), ok ? "1" : "0"].joined(separator: "\t")
        }

        static func parse(_ text: String) -> ToolCallEvent? {
            let parts = text.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 5, parts[0] == marker else { return nil }
            switch parts[1] {
            case "start":
                return ToolCallEvent(kind: .start, callId: String(parts[2]),
                                     name: String(parts[3]), label: String(parts[4]))
            case "done":
                guard parts.count >= 7,
                      let seconds = TimeInterval(String(parts[5])) else { return nil }
                return ToolCallEvent(kind: .done, callId: String(parts[2]),
                                     name: String(parts[3]), label: String(parts[4]),
                                     seconds: seconds, ok: parts[6] == "1")
            default:
                return nil
            }
        }
    }

    /// 审批请求事件（工具权限档位“每次询问”+ minis-config 写操作）：经 onEvent
    /// 交给聊天页弹现有 ApprovalSheetView，批了/拒了在聊天页结算。
    /// payload 是 base64 JSON（值里可能含任意字符，不能走 \t 分隔）；
    /// 与 ToolCallEvent（开始/完成行）是两条通道，前缀不同。
    struct ToolApprovalEvent {
        enum Kind: String { case tool, config }
        static let marker = "\u{1}oq-approval\u{1}"

        /// tool：一次被“每次询问”拦下的工具调用（批了聊天页用 preApproved 重跑一次）。
        struct Tool: Codable {
            var callId: String
            var name: String
            var argumentsJSON: String
            var agentId: String
            var workDir: String
            var label: String
        }
        /// config：一次要批的 minis-config 写操作（批了调 applyApproved，拒了调 recordRejection）。
        struct Config: Codable {
            var key: String
            var value: String
            var oldValue: String
            var sensitive: Bool
            var caption: String
            var agentId: String
        }

        static func encodeTool(callId: String, name: String, argumentsJSON: String,
                               agentId: String, workDir: String, label: String) -> String {
            encode(kind: .tool, payload: Tool(callId: callId, name: name,
                                              argumentsJSON: argumentsJSON, agentId: agentId,
                                              workDir: workDir, label: label))
        }

        static func encodeConfig(pending: MinisConfig.PendingChange, agentId: String) -> String {
            encode(kind: .config, payload: Config(key: pending.key, value: pending.value,
                                                  oldValue: pending.oldValue,
                                                  sensitive: pending.sensitive,
                                                  caption: pending.caption, agentId: agentId))
        }

        private static func encode<T: Encodable>(kind: Kind, payload: T) -> String {
            guard let data = try? JSONEncoder().encode(payload) else { return "" }
            return [marker, kind.rawValue, data.base64EncodedString()].joined(separator: "\t")
        }

        /// 解析：返回 kind 与待解码的 payload 数据，调用方按 kind 解成 Tool / Config。
        static func parse(_ text: String) -> (kind: Kind, data: Data)? {
            let parts = text.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0] == marker,
                  let kind = Kind(rawValue: String(parts[1])),
                  let data = Data(base64Encoded: String(parts[2]))
            else { return nil }
            return (kind, data)
        }
    }

    /// 工具调用行上的文字：工具名 + 关键参数（命令/网址/标题），压成一行、
    /// 截到 48 字以内。只作显示，不影响执行。
    static func toolLabel(name: String, argumentsJSON: String) -> String {
        let args = (try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8))
                    as? [String: Any]) ?? [:]
        func oneLine(_ s: String, _ max: Int = 48) -> String {
            let t = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return t.count <= max ? t : String(t.prefix(max)) + "…"
        }
        func host(_ raw: String) -> String { URL(string: raw)?.host ?? raw }
        switch name {
        case serverCommandName:
            let cmd = (args["command"] as? String) ?? ""
            return cmd.isEmpty ? "执行服务器命令" : "执行命令 \(oneLine(cmd))"
        case browseServerName:
            let action = (args["action"] as? String) ?? ""
            if action == "navigate", let url = args["url"] as? String {
                return "打开网页 \(oneLine(host(url), 40))"
            }
            return action.isEmpty ? "用服务器浏览器" : "用服务器浏览器 \(oneLine(action, 40))"
        case fetchName:
            let url = (args["url"] as? String) ?? ""
            return url.isEmpty ? "抓取网页" : "抓取网页 \(oneLine(host(url), 40))"
        case "device_calendar":
            let t = (args["title"] as? String) ?? ""
            return t.isEmpty ? "添加日程" : "添加日程 \(oneLine(t, 32))"
        case "device_reminder":
            let t = (args["title"] as? String) ?? ""
            return t.isEmpty ? "添加提醒" : "添加提醒 \(oneLine(t, 32))"
        case "device_photos":
            return "查看最近照片"
        case "device_clipboard":
            return (args["action"] as? String) == "write" ? "写入剪贴板" : "读取剪贴板"
        case "device_location":
            return "读取当前位置"
        case "device_contacts":
            let n = (args["name"] as? String) ?? ""
            return n.isEmpty ? "查找联系人" : "查找联系人 \(oneLine(n, 32))"
        case spawnSubagentName:
            let a = (args["agent"] as? String) ?? ""
            return a.isEmpty ? "派给子智能体" : "派给子智能体 \(oneLine(a, 32))"
        case MinisConfig.getName:
            let p = (args["path"] as? String) ?? ""
            return p.isEmpty ? "读设置" : "读设置 \(oneLine(p, 40))"
        case MinisConfig.setName:
            let p = (args["path"] as? String) ?? ""
            let v = (args["value"] as? String) ?? ""
            return p.isEmpty ? "改设置" : "改设置 \(oneLine(p, 32)) = \(oneLine(v, 24))"
        case MinisConfig.listName:
            return "列出可改的设置"
        default:
            return name
        }
    }

    /// 执行结果是不是工具本身失败（参数错/调不通/被拒绝）：执行完了但命令退出码
    /// 非 0 不算失败，模型自己看退出码定。
    private static func looksLikeFailure(_ result: String) -> Bool {
        ["参数不对", "调用服务器失败", "服务器浏览器操作失败",
         "抓取失败", "未知工具", "子智能体没配好",
         "设置接口没开", "没有这个设置项", "值不对"]
            .contains { result.hasPrefix($0) }
    }

    /// 执行一次工具调用，返回给模型看的文本结果。
    /// workDir 是智能体的工作文件夹（""=团队工作区）：服务器命令在那个目录里跑。
    /// 计时是真实的：开始/完成各发一个 ToolCallEvent（聊天页画调用行），
    /// 耗时 = 本次 execute 的实测时长，不写死。
    /// preApproved = 用户刚在审批卡上批过这次调用（聊天页重跑时传 true），跳过档位检查。
    static func execute(name: String, argumentsJSON: String,
                        agentId: String, server: ServerConfig,
                        workDir: String = "",
                        onEvent: ((String, Data?) -> Void)? = nil,
                        preApproved: Bool = false) async -> String {
        // minis-config 三个工具：转给 MinisConfig（它自己管总开关与审批门），
        // 不走下面的通用权限档位（minis-config 有自己的审批逻辑）。
        if name == MinisConfig.getName || name == MinisConfig.setName || name == MinisConfig.listName {
            return await executeMinisConfig(name: name, argumentsJSON: argumentsJSON,
                                            agentId: agentId, onEvent: onEvent)
        }
        // 通用权限档位（PermissionsStore）：执行前先查，默认“每次询问”。
        // 只拦登记在册的工具名；未知工具名直接走原路（回“未知工具”），不弹卡。
        // 提问卡（user_ask）不经过这里，bypass-all 只覆盖工具审批，不覆盖提问卡。
        if !preApproved, PermissionsStore.items.contains(where: { $0.id == name }) {
            switch PermissionsStore.shared.level(for: name) {
            case .denied:
                // 禁止：直接拒绝，不执行；调用行记一笔红叉，让用户看到这次调用被拦了。
                let label = toolLabel(name: name, argumentsJSON: argumentsJSON)
                let callId = UUID().uuidString
                onEvent?(ToolCallEvent.encodeStart(callId: callId, name: name,
                                                   label: "已禁止：\(label)"), nil)
                onEvent?(ToolCallEvent.encodeDone(callId: callId, name: name,
                                                  label: "已禁止：\(label)",
                                                  seconds: 0, ok: false), nil)
                return "这个工具已被禁止：\(name)（去设置 → 权限里把它的档位改成“每次询问”或“跳过审批”再试）。不要重复调用。"
            case .ask:
                // 每次询问：本次不执行，把调用请求经 onEvent 交给聊天页弹审批卡；
                // 模型先结束本轮，等用户批复结果当新消息回来（批了聊天页用 preApproved 重跑）。
                onEvent?(ToolApprovalEvent.encodeTool(
                    callId: UUID().uuidString, name: name, argumentsJSON: argumentsJSON,
                    agentId: agentId, workDir: workDir,
                    label: toolLabel(name: name, argumentsJSON: argumentsJSON)), nil)
                return "（调用 \(toolLabel(name: name, argumentsJSON: argumentsJSON)) 已弹审批卡，等用户批复：请先结束本轮，不要重复调用；批复结果会当作新消息发给你。）"
            case .bypass:
                break
            }
        }
        let callId = UUID().uuidString
        let label = toolLabel(name: name, argumentsJSON: argumentsJSON)
        let started = Date()
        onEvent?(ToolCallEvent.encodeStart(callId: callId, name: name, label: label), nil)
        let result = await run(name: name, argumentsJSON: argumentsJSON,
                               agentId: agentId, server: server,
                               workDir: workDir, onEvent: onEvent)
        onEvent?(ToolCallEvent.encodeDone(callId: callId, name: name, label: label,
                                          seconds: Date().timeIntervalSince(started),
                                          ok: !looksLikeFailure(result)), nil)
        return result
    }

    /// minis-config 三个工具的转调（execute 的一部分，单独拆出来免得主流程太长）。
    /// 读 / list 直接回文本；写要审批时不把 NEEDS_APPROVAL 串原样丢给模型——
    /// 发一个审批事件给聊天页弹卡（批了调 applyApproved，拒了调 recordRejection），
    /// 模型只拿到“等批复”的回执，批复结果当新消息续轮。
    private static func executeMinisConfig(name: String, argumentsJSON: String,
                                           agentId: String,
                                           onEvent: ((String, Data?) -> Void)? = nil) async -> String {
        guard let store = sharedStore else {
            return "设置接口没接上当前会话的存储，读/改都没执行（请从聊天里再试一次）。"
        }
        let callId = UUID().uuidString
        let label = toolLabel(name: name, argumentsJSON: argumentsJSON)
        let started = Date()
        onEvent?(ToolCallEvent.encodeStart(callId: callId, name: name, label: label), nil)
        let result = await MinisConfig.handleToolCall(
            name: name, argumentsJSON: argumentsJSON, store: store,
            agentName: sharedAgentName.isEmpty ? agentId : sharedAgentName)
        let seconds = Date().timeIntervalSince(started)
        if result.hasPrefix("NEEDS_APPROVAL:") {
            guard let pending = await configPending(from: argumentsJSON, store: store) else {
                onEvent?(ToolCallEvent.encodeDone(callId: callId, name: name, label: label,
                                                  seconds: seconds, ok: false), nil)
                return "（这个改动对应的设置项找不到了，没弹卡，也没改。）"
            }
            onEvent?(ToolApprovalEvent.encodeConfig(pending: pending, agentId: agentId), nil)
            onEvent?(ToolCallEvent.encodeDone(callId: callId, name: name,
                                              label: label + "（等批复）",
                                              seconds: seconds, ok: true), nil)
            return "（\(label) 已弹审批卡，等用户批复：请先结束本轮，不要重复调用；批复结果会当作新消息发给你。）"
        }
        onEvent?(ToolCallEvent.encodeDone(callId: callId, name: name, label: label,
                                          seconds: seconds, ok: !looksLikeFailure(result)), nil)
        return result
    }

    /// 从 set 调用的参数 + 当前存储拼出 PendingChange（给审批事件用；
    /// handleToolCall 的 NEEDS_APPROVAL 串里只有 key=value，旧值/敏感/说明要这里补）。
    private static func configPending(from argumentsJSON: String,
                                      store: AppStore) async -> MinisConfig.PendingChange? {
        guard let data = argumentsJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = obj["path"] as? String,
              let value = obj["value"] as? String,
              let old = await MinisConfig.read(store: store, path: path)
        else { return nil }
        return MinisConfig.PendingChange(key: path, value: value, oldValue: old,
                                         sensitive: MinisConfig.isSensitive(path: path),
                                         caption: (obj["caption"] as? String) ?? "")
    }

    /// 真正的执行体（execute 只包一层计时 + 事件，不动这里的逻辑）。
    private static func run(name: String, argumentsJSON: String,
                            agentId: String, server: ServerConfig,
                            workDir: String = "",
                            onEvent: ((String, Data?) -> Void)? = nil) async -> String {
        switch name {
        case serverCommandName:
            guard let data = argumentsJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let command = obj["command"] as? String, !command.isEmpty
            else { return "参数不对：缺 command" }
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
            return await DeviceTools.addCalendarEvent(
                title: title, startISO: start,
                durationMinutes: (obj["durationMinutes"] as? Int) ?? 60,
                notes: (obj["notes"] as? String) ?? "")
        case "device_reminder":
            guard let data = argumentsJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let title = obj["title"] as? String, !title.isEmpty
            else { return "参数不对：device_reminder 要 title" }
            return await DeviceTools.addReminder(
                title: title, notes: (obj["notes"] as? String) ?? "")
        case "device_photos":
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
            return await DeviceTools.currentLocation()
        case "device_contacts":
            guard let data = argumentsJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = obj["name"] as? String, !name.isEmpty
            else { return "参数不对：device_contacts 要 name" }
            return await DeviceTools.searchContacts(name: name)
        case spawnSubagentName:
            guard let spawn = Self.sharedSpawn else {
                return "子智能体没配好：这一轮不能派活"
            }
            guard let data = argumentsJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ref = obj["agent"] as? String, !ref.isEmpty,
                  let task = obj["task"] as? String, !task.isEmpty
            else { return "参数不对：spawn_subagent 要 agent（名字或 id）和 task" }
            return await spawn(ref, task)
        case fetchName:
            guard let data = argumentsJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let raw = obj["url"] as? String, let url = URL(string: raw)
            else { return "参数不对：缺 url" }
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
