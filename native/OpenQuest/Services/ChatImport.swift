import Foundation

/// 会话导入（DDchat 式）：DeepSeek / Chatbox 导出的 JSON。
/// 两种格式都认：顶层数组或 {sessions/conversations/chats/data: [...]}；
/// 每条会话取 title + messages[{role, content}]（content 是字符串或 parts 数组）。
/// 用户消息照原样进；智能体消息挂到一个新建的「导入助手」名下（只在真有
/// 智能体消息时才建，由用户这次导入触发，不预置）。
enum ChatImport {
    struct Imported {
        var title: String
        var messages: [(role: String, text: String)]
    }

    static func parse(_ data: Data) -> [Imported] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var raw: [[String: Any]] = []
        if let arr = root as? [[String: Any]] { raw = arr }
        else if let dict = root as? [String: Any] {
            for key in ["sessions", "conversations", "chats", "data"] {
                if let arr = dict[key] as? [[String: Any]] { raw = arr; break }
            }
            if raw.isEmpty, dict["messages"] != nil { raw = [dict] }
        }
        var out: [Imported] = []
        for item in raw {
            let title = (item["title"] as? String) ?? (item["name"] as? String) ?? "导入的会话"
            guard let msgs = item["messages"] as? [[String: Any]] else { continue }
            var list: [(String, String)] = []
            for m in msgs {
                guard let role = m["role"] as? String else { continue }
                let text = extractText(m["content"])
                guard !text.isEmpty else { continue }
                list.append((role, text))
            }
            guard !list.isEmpty else { continue }
            out.append(Imported(title: title, messages: list))
        }
        return out
    }

    /// content 可能是字符串，也可能是 [{type:"text", text:"..."}]。
    private static func extractText(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let arr = v as? [[String: Any]] {
            return arr.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ""
    }

    /// 导入进 store：返回导入的会话数。
    @MainActor
    static func importInto(_ store: AppStore, sessions: [Imported]) -> Int {
        var assistantAgent: Agent?
        func assistant() -> Agent {
            if let a = assistantAgent { return a }
            if let existing = store.agents.first(where: { $0.name == "导入助手" }) {
                assistantAgent = existing
                return existing
            }
            let a = Agent(name: "导入助手", tintHue: 0.62)
            store.agents.append(a)
            assistantAgent = a
            return a
        }
        var count = 0
        for s in sessions {
            var memberIds: [UUID] = []
            if s.messages.contains(where: { $0.role == "assistant" }) {
                memberIds = [assistant().id]
            } else {
                // 只有用户消息：也要有个成员才进得去聊天页。
                memberIds = [assistant().id]
            }
            var conv = Conversation(title: s.title, memberIds: memberIds)
            for m in s.messages {
                if m.role == "user" {
                    conv.messages.append(Message(senderId: "user", text: m.text))
                } else {
                    conv.messages.append(Message(senderId: memberIds[0].uuidString, text: m.text))
                }
            }
            store.conversations.insert(conv, at: 0)
            count += 1
        }
        if count > 0 { store.save() }
        return count
    }
}
