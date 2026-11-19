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
}

/// 一个模型供应商：用户自己添加——名字、接口地址（OpenAI 兼容）、Key；
/// 下面可再添加任意个模型。App 只预置入口，不预置 Key。
struct ModelProvider: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String                 // 如 Agnes、智谱、DeepSeek，或用户自填
    var baseURL: String              // 如 https://api.agnes-ai.cn/v1
    var models: [AIModel] = []
    // Key 不进 JSON 快照，单独存 Keychain（见 KeychainHelper），这里只留引用 id。
    var keyRef: String { id.uuidString }
}

/// 供应商下面的一个模型。
struct AIModel: Identifiable, Codable, Equatable {
    var id: String                   // 模型 id，如 agnes-2.5-flash
    var displayName: String = ""     // 显示名，空则用 id
    var name: String { displayName.isEmpty ? id : displayName }
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
}
