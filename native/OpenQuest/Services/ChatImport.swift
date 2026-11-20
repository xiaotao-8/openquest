import Foundation
import SwiftUI

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

    // MARK: - DeepSeek 链接导入（DDchat 补 5）

    /// 从 DeepSeek 分享/备份链接导入。2.12.0 更新说明：「在 DeepSeek 复制备份下载链接，
    /// 粘贴到 DDchat 就能预览并导入，省去手动下载文件的步骤。」
    /// 链接只由用户主动粘贴才拉取，不后台抓。成功返回解析出的会话（调用方先预览再确认导入）；
    /// 失败返回明确原因，不静默丢掉。
    enum DeepSeekLinkError: Error, LocalizedError {
        case invalidURL
        case notDeepSeekLink
        case network(String)
        case badResponse(Int)
        case noContent

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "链接不对：粘贴一个完整的 DeepSeek 链接，如 https://chat.deepseek.com/share/…"
            case .notDeepSeekLink:
                return "这不是 DeepSeek 的链接：只认 deepseek.com 的分享/备份链接。"
            case .network(let msg):
                return "拉取链接失败：\(msg)，检查网络后重试。"
            case .badResponse(let code):
                return "DeepSeek 返回 \(code)：链接可能过期了，重新在 DeepSeek 里复制一份再试。"
            case .noContent:
                return "链接里没找到可导入的对话内容：确认复制的是 DeepSeek 的备份下载链接（不是聊天页地址），重新复制再试。"
            }
        }
    }

    /// 拉取链接并解析。链接里的 id（分享 id / 下载文件 id）只用来在失败时定位问题，不另作他用。
    static func fetchDeepSeekLink(_ raw: String) async -> Result<[Imported], DeepSeekLinkError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme, scheme == "http" || scheme == "https"
        else { return .failure(.invalidURL) }
        guard let host = url.host, host.contains("deepseek.com") else {
            return .failure(.notDeepSeekLink)
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        req.setValue("application/json, text/html", forHTTPHeaderField: "Accept")
        let data: Data
        let status: Int
        do {
            let (d, resp) = try await Net.session.data(for: req)
            data = d
            status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            return .failure(.network(error.localizedDescription))
        }
        guard status == 200 else { return .failure(.badResponse(status)) }
        // 1) 链接直接返回 JSON（备份下载链接）：走同一 parse。
        let parsed = parse(data)
        if !parsed.isEmpty { return .success(parsed) }
        // 2) 链接返回分享页 HTML：从页里嵌的 JSON 中抠会话（找含 "messages" 的对象）。
        if let html = String(data: data, encoding: .utf8),
           let embedded = extractEmbeddedSessionJSON(from: html) {
            let fromPage = parse(embedded)
            if !fromPage.isEmpty { return .success(fromPage) }
        }
        return .failure(.noContent)
    }

    /// 在 HTML 里找含 `"messages"` 的 JSON 对象：从每个 `"messages"` 出现处往回找 `{`，
    /// 再花括号配对抠出候选对象，逐个试解析。只试前 8 处，避免在超大页面上死抠。
    private static func extractEmbeddedSessionJSON(from html: String) -> Data? {
        var searchFrom = html.startIndex
        var tried = 0
        while tried < 8, let msgRange = html[searchFrom...].range(of: "\"messages\"") {
            tried += 1
            // 往回找这个对象/数组的起始 `{`（跳过转义与字符串内的花括号是近似处理：
            // 候选对象解析失败就继续找下一处，不会误报）。
            var open: String.Index? = nil
            var j = msgRange.lowerBound
            while j > html.startIndex {
                j = html.index(before: j)
                if html[j] == "{" { open = j; break }
                if html[j] == "}" { break }
            }
            if let open {
                var depth = 0
                var k = open
                while k < html.endIndex {
                    if html[k] == "{" { depth += 1 }
                    if html[k] == "}" {
                        depth -= 1
                        if depth == 0 {
                            let candidate = String(html[open...k])
                            if let data = candidate.data(using: .utf8) { return data }
                            break
                        }
                    }
                    k = html.index(after: k)
                }
            }
            searchFrom = msgRange.upperBound
        }
        return nil
    }
}

/// 粘贴 DeepSeek 链接导入页：粘贴链接 → 拉取并预览会话数与标题 → 确认导入。
/// 挂载点（给协调员）：ChatListView / HomeView 的导入入口旁加一行“粘贴 DeepSeek 链接”，
/// 以 sheet 弹出本页；本文件不改 ChatListView / HomeView。
struct DeepSeekLinkImportView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    @State private var link = ""
    @State private var busy = false
    @State private var error: String?
    @State private var preview: [ChatImport.Imported] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("粘贴 DeepSeek 分享 / 备份链接", text: $link)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Button(busy ? "正在拉取…" : "拉取并预览") {
                        Task { await fetch() }
                    }
                    .disabled(busy || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if busy { ProgressView() }
                } footer: {
                    Text("在 DeepSeek 里复制备份下载链接，粘贴到这里就能预览并导入，不用先把文件下载下来。链接只在你点拉取时访问一次。")
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.subheadline)
                    }
                }
                if !preview.isEmpty {
                    Section("预览（共 \(preview.count) 个会话）") {
                        ForEach(Array(preview.enumerated()), id: \.offset) { _, s in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title)
                                Text("\(s.messages.count) 条消息")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section {
                        Button("确认导入 \(preview.count) 个会话") {
                            let n = ChatImport.importInto(store, sessions: preview)
                            preview = []
                            link = ""
                            error = n > 0 ? nil : "导入失败：内容是空的。"
                            if n > 0 { dismiss() }
                        }
                    }
                }
            }
            .navigationTitle("导入 DeepSeek 链接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func fetch() async {
        busy = true
        error = nil
        preview = []
        defer { busy = false }
        switch await ChatImport.fetchDeepSeekLink(link) {
        case .success(let sessions):
            preview = sessions
        case .failure(let e):
            error = e.localizedDescription
        }
    }
}
