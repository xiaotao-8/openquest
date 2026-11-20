import SwiftUI

/// 记忆页（FishPocket/Minis 式条目制）：看记忆条目、问记忆、忘掉、历史/恢复。
/// 存在服务器上该智能体工作目录的 MEMORY.md 里，走 MemoryStore（exec 读写）。
/// 问记忆走 GuardedTurn——人设 + 拒绝拦截和聊天里同一套，不绕过。
struct MemoryView: View {
    @EnvironmentObject var store: AppStore
    let agentId: UUID

    @State private var entries: [MemoryEntry] = []
    @State private var busy = false
    @State private var status: String?
    @State private var newText = ""
    @State private var newTopic = ""
    @State private var question = ""
    @State private var answer: String?
    @State private var asking = false
    @State private var snaps: [(stamp: String, count: Int, content: String)] = []
    @State private var showingHistory = false

    private var agent: Agent? { store.agent(id: agentId) }

    var body: some View {
        List {
            Section("问记忆") {
                HStack {
                    TextField("问问它记得什么，如：我喜欢什么颜色", text: $question)
                    Button("问") { Task { await askMemory() } }
                        .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || asking)
                }
                if asking { ProgressView() }
                if let answer {
                    Text(answer).font(.subheadline)
                }
            }
            Section("记一条") {
                TextField("内容", text: $newText)
                TextField("主题（可空）", text: $newTopic)
                Button("记下来") { Task { await addEntry() } }
                    .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }
            Section("记忆条目") {
                if entries.isEmpty {
                    Text("还没有记忆条目。聊天里智能体记住的事、你在这里记的，都会列在这里。")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { e in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(e.text)
                        HStack(spacing: 8) {
                            Text(e.added).font(.caption2)
                            if !e.topic.isEmpty { Text(e.topic).font(.caption2) }
                            Text(e.by == "self" ? "它记的" : "你记的").font(.caption2)
                            Text(e.scope == "team" ? "全队" : "仅它").font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("忘掉", role: .destructive) { Task { await forget(e) } }
                    }
                }
            }
            Section {
                Button("历史 / 恢复") { Task { await loadHistory() } }
                if let status {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("\(agent?.name ?? "智能体")的记忆")
        .task { await reload() }
        .sheet(isPresented: $showingHistory) {
            NavigationStack {
                List {
                    if snaps.isEmpty {
                        Text("还没有历史快照。每次改记忆都会先留一份快照。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(snaps.enumerated()), id: \.offset) { _, snap in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(snap.stamp)
                            Text("\(snap.count) 条").font(.caption).foregroundStyle(.secondary)
                            Button("恢复到这份") { Task { await restore(snap) } }
                                .font(.subheadline)
                        }
                    }
                }
                .navigationTitle("历史快照")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("关闭") { showingHistory = false }
                    }
                }
            }
        }
    }

    private func reload() async {
        guard let a = agent else { return }
        entries = await MemoryStore.load(agentId: a.id.uuidString, workDir: a.workDir,
                                         server: store.server)
    }

    private func addEntry() async {
        guard let a = agent else { return }
        busy = true
        defer { busy = false }
        let ok = await MemoryStore.add(agentId: a.id.uuidString, workDir: a.workDir,
                                       server: store.server,
                                       text: newText.trimmingCharacters(in: .whitespaces),
                                       by: "user", scope: "bot",
                                       topic: newTopic.trimmingCharacters(in: .whitespaces))
        status = ok ? "记下了" : "记失败：服务器没连上"
        if ok { newText = ""; newTopic = "" }
        await reload()
    }

    private func forget(_ e: MemoryEntry) async {
        guard let a = agent else { return }
        let ok = await MemoryStore.forget(agentId: a.id.uuidString, workDir: a.workDir,
                                          server: store.server, entryId: e.id)
        status = ok ? "已忘掉" : "忘失败：服务器没连上"
        await reload()
    }

    private func loadHistory() async {
        guard let a = agent else { return }
        snaps = await MemoryStore.history(agentId: a.id.uuidString, workDir: a.workDir,
                                          server: store.server)
        showingHistory = true
    }

    private func restore(_ snap: (stamp: String, count: Int, content: String)) async {
        guard let a = agent else { return }
        let ok = await MemoryStore.restore(agentId: a.id.uuidString, workDir: a.workDir,
                                           server: store.server, content: snap.content)
        status = ok ? "已恢复到 \(snap.stamp)" : "恢复失败：服务器没连上"
        showingHistory = false
        await reload()
    }

    /// 问记忆：把条目拼进问题里，走 GuardedTurn 跑一轮（人设+拒绝拦截照常）。
    private func askMemory() async {
        guard let a = agent,
              let p = store.providers.first(where: { $0.id.uuidString == a.providerKey }),
              !a.modelId.isEmpty else {
            status = "先给这个智能体选好供应商和模型"
            return
        }
        asking = true
        defer { asking = false }
        let context = entries.map { "- \($0.text)" }.joined(separator: "\n")
        let prompt = """
        下面是你的记忆条目（可能为空）：
        \(context.isEmpty ? "（暂无记忆）" : context)

        问题：\(question.trimmingCharacters(in: .whitespaces))
        只按上面这些记忆回答；没有相关记忆就直说不知道，不要编。
        """
        let runner = AgentRunner(provider: p, server: store.server)
        let result = await GuardedTurn.run(
            runner: runner, agent: a, history: [(role: "user", content: prompt)],
            skillsContext: store.skillsContext(for: a.id)) { _, _ in }
        switch result {
        case .text(let t, _, _):
            answer = t
        case .card:
            answer = "（它反过来问了个问题，去聊天里回答它吧）"
        }
    }
}

/// 全局记忆页（Minis GLOBAL.md + 每日日志，AIChatViewModel+MemoryTools.swift：
/// GLOBAL.md 是用户自己维护的背景信息，不是 standing 指令；最近 3 条有内容
/// 的每日日志进系统提示）。存在本地 AppStore 快照里；
/// 服务器端按智能体的 MEMORY.md 是另一套（上面那个 MemoryView），不冲突。
struct GlobalMemoryView: View {
    @EnvironmentObject var store: AppStore
    @State private var draft = ""
    @State private var savedNote: String?
    @State private var showingAddLog = false
    @State private var logDraft = ""
    @State private var editingLogId: UUID?

    private var dayFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy 年 M 月 d 日"
        return f
    }

    var body: some View {
        List {
            Section {
                Text("全局记忆是背景信息，不是命令：如果和你最新说的话冲突，以最新说的为准。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("全局记忆（GLOBAL.md）") {
                TextEditor(text: $draft)
                    .frame(minHeight: 180)
                    .autocorrectionDisabled()
                HStack {
                    Button("保存全局记忆") {
                        store.setGlobalMemory(draft)
                        savedNote = "已保存"
                    }
                    .disabled(draft == store.globalMemory)
                    Spacer()
                    if let savedNote {
                        Text(savedNote).font(.caption).foregroundStyle(.green)
                    }
                }
            }
            Section("每日日志") {
                if store.dailyLogs.isEmpty {
                    Text("还没有每日日志。每天记一条（今天做了什么、有什么新情况），智能体聊天时会参考最近 3 条。")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.dailyLogs) { log in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(dayFormatter.string(from: log.day))
                            .font(.subheadline.weight(.semibold))
                        Text(log.content)
                            .font(.footnote).foregroundStyle(.secondary)
                            .lineLimit(3)
                        Button("改这条") {
                            editingLogId = log.id
                            logDraft = log.content
                            showingAddLog = true
                        }
                        .font(.subheadline)
                    }
                }
                .onDelete { idx in
                    for i in idx { store.deleteDailyLog(id: store.dailyLogs[i].id) }
                }
                Button("写今日日志") {
                    editingLogId = nil
                    logDraft = ""
                    showingAddLog = true
                }
            }
        }
        .navigationTitle("记忆")
        .onAppear { draft = store.globalMemory }
        .sheet(isPresented: $showingAddLog) {
            NavigationStack {
                Form {
                    TextEditor(text: $logDraft)
                        .frame(minHeight: 220)
                        .autocorrectionDisabled()
                }
                .navigationTitle(editingLogId == nil ? "今日日志" : "改日志")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showingAddLog = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            let day = editingLogId.flatMap { id in
                                store.dailyLogs.first { $0.id == id }?.day
                            } ?? Date()
                            store.addDailyLog(content: logDraft.trimmingCharacters(in: .whitespaces),
                                              day: day)
                            showingAddLog = false
                        }
                        .disabled(logDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }
}
