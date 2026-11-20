import Foundation

/// 一个智能体：名字、人设（Soul）、模型都由用户自己建、自己配，App 不预置任何一个。
struct Agent: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var soul: String = ""            // 人设/规矩，最高优先级，用户自己写
    var providerKey: String = ""     // 服务商标识，如 agnes / zhipu / deepseek
    var modelId: String = ""         // 该智能体用的模型
    var tintHue: Double = 0.6        // 头像底色（首字 disc，不用 emoji、不用 App 图标）
    var initial: String { String(name.prefix(1)) }
    // 思考档位：""=跟模型默认，off/low/medium/high（DDchat/Minis/FishPocket 三家都有）。
    var effort: String = ""
    // 生成参数（DDchat）：前置词/后置词包在每条用户消息外；temperature/Top-P 进请求体。
    var prefix: String = ""
    var suffix: String = ""
    var temperature: Double = 1.0
    var topP: Double = 1.0
    // 上下文：最多带几条历史消息（0=不限）；满了自动压缩=截掉最旧的并打标记。
    var contextLength: Int = 0
    var autoCompress: Bool = false
    // 工作文件夹（FishPocket）：""=团队工作区；私有智能体必须另指一个不重叠的文件夹。
    var workDir: String = ""
    var isPrivate: Bool = false
}

/// 卡片（提问卡 / 投票卡 / 审批卡）：智能体发起，用户点选项行作答。
/// 按 Minis 的 user_ask 卡片样式：整张卡、一句问题、2–4 个选项行（短标签+一行描述），
/// 提问卡可多选；审批卡是操作+影响说明；投票卡点选即计票。
struct CardPayload: Codable, Equatable {
    enum Kind: String, Codable { case ask, vote, approval }
    var kind: Kind
    var question: String
    var options: [CardOption] = []
    var multiSelect: Bool = false
    var resolved: [String] = []      // 用户已选的 option id；非空 = 已作答
    // 提问卡补全（Minis）：倒计时（分钟，0=不限）、作答截止时间、问题旁小标签、
    // 多题向导（后面的题）。label/header 各 ≤12 字，解析时截断；问题是一整句，不截断。
    var timeoutMinutes: Int = 5
    var deadline: Date? = nil
    var header: String = ""
    var recommendedId: String = ""     // 旧卡片兼容：角标现在按 Minis 打在第一个选项上；超时建议仍优先用它（旧卡片），没有就取第一个
    var extraQuestions: [CardPayload] = []
    // 审批卡补全（Minis confirm）：等宽字体的精确动作、影响行、风险等级。
    var actionText: String = ""
    var impact: String = ""
    var risk: String = "low"         // low / medium / high（medium 橙、high 红，只定颜色）
}

struct CardOption: Identifiable, Codable, Equatable {
    var id: String
    var label: String
    var detail: String = ""
}

/// 一条消息。senderId 为 "user"、"system" 或某个智能体的 id。
struct Message: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var senderId: String
    var text: String
    var reasoning: String? = nil     // 深度思考过程，回复上方一个可展开的块，中文显示
    var date: Date = Date()
    var card: CardPayload? = nil     // 带卡片的消息渲染成卡片
    var imageJPEG: Data? = nil       // 用户发的图片（压缩后）：气泡显示 + 发给视觉模型
    var fileName: String? = nil      // 用户发的文件名
    var fileText: String? = nil      // 文本类文件内容（截取后随消息发给模型）
    var usagePrompt: Int? = nil      // 本条回复的用量（SSE usage 段）：输入 tokens
    var usageCompletion: Int? = nil  // 输出 tokens
    var eventKind: String? = nil     // 群轮次事件行：failed / missed / admin-passed / paused
    var variantOf: UUID? = nil       // 分支：同组重新生成的回复共用一个根 id
    var variantIndex: Int = 0        // 分支序号（0=第一版）
}

/// 一个模型供应商：用户自己添加——名字、接口地址（OpenAI 兼容）、Key；
/// 下面可再添加任意个模型。App 只预置入口，不预置 Key。
struct ModelProvider: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String                 // 如 Agnes、智谱、DeepSeek，或用户自填
    var baseURL: String              // 如 https://api.agnes-ai.cn/v1
    var models: [AIModel] = []
    // 自定义请求头（DDchat）：每行一个 "Key: Value"，该供应商的每次请求都带上。
    var customHeaders: String = ""
    /// 解析 customHeaders：每行 "Key: Value"，没冒号、键或值为空的行直接忽略。
    var parsedCustomHeaders: [String: String] {
        var out: [String: String] = [:]
        for line in customHeaders.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let k = parts[0].trimmingCharacters(in: .whitespaces)
            let v = parts[1].trimmingCharacters(in: .whitespaces)
            guard !k.isEmpty, !v.isEmpty else { continue }
            out[k] = v
        }
        return out
    }
    // Key 不进 JSON 快照，单独存 Keychain（见 KeychainHelper），这里只留引用 id。
    var keyRef: String { id.uuidString }
}

/// 供应商下面的一个模型。
struct AIModel: Identifiable, Codable, Equatable {
    var id: String                   // 模型 id，如 agnes-2.5-flash
    var displayName: String = ""     // 显示名，空则用 id
    var name: String { displayName.isEmpty ? id : displayName }
    // 能力自动检测（DDchat）：从模型 id/名字推断，只作提示，不拦着用。
    // nil=没检测出（按支持处理，控件照常显示）；true/false=检测有/没有。
    var supportsReasoning: Bool? = nil  // 深度思考（思考档位）
    var supportsVision: Bool? = nil     // 视觉理解（发图片）
}

/// 一个连接工具（连接器）：只装国内服务——飞书、钉钉、语雀、Gitee、
/// 博查搜索、阿里云等；全部默认关闭，用户手动开。境外服务不作依赖、不作默认。
/// 一个技能（Skill）：用户自己写或导入的一段指令，挂到智能体身上后，
/// 聊天时拼进系统指令里真正生效——不是摆设。
struct Skill: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var content: String              // 技能正文（指令）
    var agentIds: [UUID] = []        // 对哪些智能体生效
}

/// 一个 DSH 风格插件包（单文件 JSON 清单）：用户在 App 内下载/粘贴安装。
/// instruction 类把指令拼进系统提示真生效；script 类是服务器上真跑的脚本；
/// theme 类是纯网页美化，App 内用不了——安装时就拦下并标注，不糊弄。
struct Plugin: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var summary: String = ""         // 一行说明（英文会自动译成中文再存）
    var type: String = "instruction" // instruction / script / theme
    var content: String = ""         // instruction 类是指令正文；script 类是脚本正文
    var settingsURL: String = ""     // 网页设置页（有就用内嵌网页在 App 里打开）
    var enabled: Bool = false        // 默认关，全局原则
    var hasClientHalf: Bool = false  // 带网页界面部分的插件：App 内只跑主机部分
}

struct Connector: Identifiable, Codable, Equatable {
    var id: String                   // 如 feishu / dingtalk / yuque / gitee / bocha
    var name: String                 // 显示名
    var summary: String              // 一行说明
    var enabled: Bool = false        // 默认关
}

/// 内置的国内连接工具清单（只是入口，启用与授权都由用户手动来）。
let builtinConnectors: [Connector] = [
    Connector(id: "feishu",   name: "飞书",     summary: "消息、文档、多维表格"),
    Connector(id: "dingtalk", name: "钉钉",     summary: "消息、审批、考勤"),
    Connector(id: "yuque",    name: "语雀",     summary: "知识库文档读写"),
    Connector(id: "gitee",    name: "Gitee",    summary: "代码仓库、Issue"),
    Connector(id: "bocha",    name: "博查搜索", summary: "国内网页搜索"),
    Connector(id: "aliyun",   name: "阿里云",   summary: "云服务器管理"),
]

/// 定时任务（FishPocket）：按智能体或按群，到点发一条指令开工。
/// iOS 诚实做法：本地通知 + 打开 App 后执行到期的任务（后台常驻跑不了，不假装）。
/// 锁屏审批 deep link 带来的作答：哪个会话、批不批准。
struct DeepLinkApproval: Equatable {
    var convId: UUID
    var approve: Bool
}

struct ScheduledTask: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var targetKind: String = "agent"  // agent=某个智能体，room=某个群
    var targetId: UUID = UUID()       // 智能体 id 或会话 id
    var targetName: String = ""
    var title: String = ""
    var prompt: String = ""           // 到点要做的事
    var repeatKind: String = "once"   // once / daily / weekly / every
    var time: String = "09:00"        // daily/weekly 用，HH:mm
    var weekdays: [Int] = [1, 2, 3, 4, 5]  // weekly 用，周一=1
    var everyMinutes: Int = 60        // every 用
    var nextFire: Date = Date()
    var enabled: Bool = true
}

/// 用户自己的 MCP 服务器（FishPocket 自定义连接器）：一个 HTTPS 地址。
struct CustomMCP: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var url: String
    var enabled: Bool = false
}

/// 小工具 MiniApp（FishPocket）：应用 = 一个文件夹（app.json + 页面文件），
/// files 存文件名 -> 文件内容，WKWebView 用自定义协议跑起来。
struct MiniApp: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var files: [String: String] = [:]  // 如 index.html、app.json、style.css
}

/// 本机能力（FishPocket）：一能力一开关，全部默认关，开关只决定模型看不看得到
/// 这个工具；真用时还要过系统授权，拒绝就报没拿到授权。
struct DeviceCapability: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var summary: String
    var enabled: Bool = false
}

let builtinDeviceCapabilities: [DeviceCapability] = [
    DeviceCapability(id: "calendar", name: "日历", summary: "新建日程"),
    DeviceCapability(id: "reminders", name: "提醒事项", summary: "新建提醒"),
    DeviceCapability(id: "photos", name: "照片", summary: "读最近照片的数量和时间"),
    DeviceCapability(id: "clipboard", name: "剪贴板", summary: "读写剪贴板文字"),
    DeviceCapability(id: "location", name: "位置", summary: "读一次当前位置"),
    DeviceCapability(id: "contacts", name: "通讯录", summary: "按名字查联系人"),
]

/// 用户自己的服务器（阿里云香港 ECS）：智能体常驻主机。
/// 地址可改；令牌存 Keychain，不进 JSON 快照。
struct ServerConfig: Codable, Equatable {
    var host: String = "47.238.160.204"
    var port: Int = 18789
    var tokenRef: String = "server-main"
    var baseURL: String { "http://\(host):\(port)" }
}

/// 一个会话：单聊（一个智能体）或群聊（多个智能体）。
/// 侧边栏只留一个聊天列表，群和单聊混排——用户 2026-11-20 拍板。
struct Conversation: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var memberIds: [UUID] = []       // 群成员（智能体）；单聊只有一个
    var isGroup: Bool { memberIds.count > 1 }
    var messages: [Message] = []
    var pendingCard: CardPayload? = nil  // 等用户作答的卡片（提问/审批），答完清除
    var workingNote: String? = nil   // 有智能体在干活时的一行状态，显示在列表该行下面
    var lastActivity: Date = Date()
    var lastPreview: String {
        messages.last?.text ?? ""
    }
    // 群聊补全（FishPocket）：群主、发言模式、群公告、群目标、停下的成员。
    var adminId: UUID? = nil
    var speakMode: String = "everyone"  // everyone=全员轮流，admin=群主先接再点名
    var notice: String = ""              // 群公告：每成员发言前先读
    var goalTitle: String = ""           // 群目标标题
    var goalStages: [String] = []        // 群目标阶段
    var goalCurrent: Int = 0             // 当前到第几个阶段
    var goalStatus: String = "active"    // active / done / stopped
    var stoppedMembers: [UUID] = []      // 被单独停下的成员
    var variantSelection: [String: Int] = [:]  // 分支显示：variantOf UUID 字符串 -> 选中的序号
    var autoReplyPending: Bool = false   // 定时任务到点：下一条用户消息已就位，打开就回
}
