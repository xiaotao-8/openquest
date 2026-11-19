import SwiftUI

/// 聊天页：消息流 + 卡片 + 输入框 + 干活小窗。
/// 群聊里智能体自己接话——发言权按「最久没发言的成员优先」轮换，不许永远同一个人；
/// 用户或成员 @ 某人时，被 @ 的人接棒。一条用户消息最多连转 3 棒，防刷屏。
struct ChatView: View {
    @EnvironmentObject var store: AppStore
    let conversationId: UUID
    @State private var input = ""
    @State private var running = false
    @State private var working: [(name: String, action: String)] = []
    @State private var showingWorkingPanel = false

    private var conversation: Conversation? {
        store.conversations.first { $0.id == conversationId }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(conversation?.messages ?? []) { m in
                            if let card = m.card {
                                CardView(card: card) { chosen in answerCard(chosen, messageId: m.id) }
                                    .id(m.id)
                            } else {
                                MessageBubble(message: m, conversation: conversation)
                                    .id(m.id)
                            }
                        }
                        if let pending = conversation?.pendingCard {
                            CardView(card: pending) { chosen in answerPendingCard(chosen) }
                        }
                    }
                    .padding(12)
                }
                .onChange(of: conversation?.messages.count ?? 0) { _, _ in
                    if let last = conversation?.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            Divider()
            HStack(spacing: 8) {
                TextField("说点什么", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                Button {
                    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty, !running else { return }
                    input = ""
                    Task { await send(text) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || running)
            }
            .padding(10)
        }
        .background(Color.black)
        .navigationTitle(conversation?.title ?? "聊天")
        .navigationBarTitleDisplayMode(.inline)
        // 干活小窗：浮在右下，显示几个人在干活；点开是大面板，写清谁在干什么。
        .overlay(alignment: .bottomTrailing) {
            if !working.isEmpty {
                Button { showingWorkingPanel = true } label: {
                    Label("\(working.count) 人在干活", systemImage: "wrench.and.screwdriver.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
                .padding(.trailing, 14).padding(.bottom, 76)
            }
        }
        .sheet(isPresented: $showingWorkingPanel) {
            NavigationStack {
                List(working, id: \.name) { w in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w.name).font(.headline)
                        Text(w.action).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("正在干活")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("关闭") { showingWorkingPanel = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: 卡片作答

    private func answerPendingCard(_ chosen: [CardOption]) {
        guard let i = store.conversations.firstIndex(where: { $0.id == conversationId }),
              let card = store.conversations[i].pendingCard else { return }
        store.conversations[i].pendingCard = nil
        store.save()
        let answer: String
        if card.kind == .approval {
            answer = chosen.first?.id == "approve" ? "批准" : "拒绝"
        } else {
            answer = chosen.map(\.label).joined(separator: "、")
        }
        Task { await send(answer) }
    }

    private func answerCard(_ chosen: [CardOption], messageId: UUID) {
        guard let ci = store.conversations.firstIndex(where: { $0.id == conversationId }),
              let mi = store.conversations[ci].messages.firstIndex(where: { $0.id == messageId })
        else { return }
        store.conversations[ci].messages[mi].card?.resolved = chosen.map(\.id)
        store.save()
    }

    // MARK: 发送与群聊轮转

    private func send(_ text: String) async {
        guard let conv = conversation else { return }
        append(Message(senderId: "user", text: text))
        running = true
        defer { running = false; working = [] }

        let members = conv.memberIds.compactMap { store.agent(id: $0) }
        guard !members.isEmpty else { return }

        var floorHolder = pickFirstSpeaker(members: members, userText: text, conv: conv)
        var hops = 0
        while let speaker = floorHolder, hops < 3 {
            hops += 1
            working = [(speaker.name, "正在回复…")]
            setWorking("\(speaker.name) 正在回复…")
            let result = await replyFrom(speaker)
            setWorking(nil)
            guard let result else { break }
            switch result {
            case .text(let reply, let reasoning):
                guard !reply.isEmpty else { return }
                append(Message(senderId: speaker.id.uuidString, text: reply, reasoning: reasoning))
                floorHolder = mentionedMember(in: reply, members: members, excluding: speaker)
            case .card(let card):
                // 卡片挂起等用户作答，本轮结束。
                if let i = store.conversations.firstIndex(where: { $0.id == conversationId }) {
                    store.conversations[i].pendingCard = card
                    store.save()
                }
                return
            }
        }
    }

    /// 第一个发言的人：用户 @ 了谁就是谁；没 @ 时选「最久没发言」的成员轮换，
    /// 保证不会永远同一个人开口（这是旧版实测翻过的车）。
    private func pickFirstSpeaker(members: [Agent], userText: String, conv: Conversation) -> Agent? {
        if let m = mentionedMember(in: userText, members: members, excluding: nil) { return m }
        var lastSpokeAt: [UUID: Int] = [:]
        for (i, msg) in conv.messages.enumerated() {
            if let uuid = UUID(uuidString: msg.senderId) { lastSpokeAt[uuid] = i }
        }
        return members.min { (lastSpokeAt[$0.id] ?? -1) < (lastSpokeAt[$1.id] ?? -1) }
    }

    private func mentionedMember(in text: String, members: [Agent], excluding: Agent?) -> Agent? {
        members.first { $0.id != excluding?.id && text.contains("@\($0.name)") }
    }

    private func replyFrom(_ agent: Agent) async -> AgentRunner.TurnResult? {
        guard let conv = conversation,
              let provider = store.providers.first(where: { $0.id.uuidString == agent.providerKey }),
              !agent.modelId.isEmpty
        else {
            return .text("（我还没配好模型，去我的设置里给我选一个供应商和模型。）", reasoning: nil)
        }
        let history: [(role: String, content: String)] = conv.messages.map { m in
            if m.senderId == "user" { return (role: "user", content: m.text) }
            if m.senderId == agent.id.uuidString { return (role: "assistant", content: m.text) }
            let name = store.agent(id: UUID(uuidString: m.senderId) ?? UUID())?.name ?? "成员"
            return (role: "user", content: "[\(name)] \(m.text)")
        }
        do {
            return try await AgentRunner(provider: provider, server: store.server)
                .reply(agent: agent, history: history)
        } catch {
            return .text("（出错了：\(error.localizedDescription)）", reasoning: nil)
        }
    }

    private func append(_ message: Message) {
        guard let i = store.conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        store.conversations[i].messages.append(message)
        store.conversations[i].lastActivity = Date()
        store.save()
    }

    private func setWorking(_ note: String?) {
        guard let i = store.conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        store.conversations[i].workingNote = note
    }
}

/// 卡片视图：整张卡 + 一句问题 + 选项行（短标签 + 一行描述），点行作答。
/// 提问卡可多选（选完点确认）；投票卡点即选；审批卡批准是绿、拒绝是红。
struct CardView: View {
    let card: CardPayload
    let onAnswer: ([CardOption]) -> Void
    @State private var picked: Set<String> = []

    private var answered: Bool { !card.resolved.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: card.kind == .approval ? "checklist" : card.kind == .vote ? "chart.bar" : "questionmark.bubble")
                Text(card.kind == .approval ? "需要你批准" : card.kind == .vote ? "投票" : "提问")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            Text(card.question).font(.body.weight(.medium))
            ForEach(card.options) { opt in
                Button {
                    if answered { return }
                    if card.multiSelect {
                        if picked.contains(opt.id) { picked.remove(opt.id) } else { picked.insert(opt.id) }
                    } else {
                        onAnswer([opt])
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(opt.label).font(.body)
                            if !opt.detail.isEmpty {
                                Text(opt.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if answered && card.resolved.contains(opt.id) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        } else if picked.contains(opt.id) {
                            Image(systemName: "checkmark.circle.fill")
                        }
                    }
                    .padding(10)
                    .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(approvalColor(opt))
            }
            if card.multiSelect && !answered {
                Button("确认") {
                    onAnswer(card.options.filter { picked.contains($0.id) })
                }
                .disabled(picked.isEmpty)
            }
            if answered {
                Text("已作答").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func approvalColor(_ opt: CardOption) -> Color {
        guard card.kind == .approval else { return .primary }
        return opt.id == "reject" ? .red : .green
    }
}

private struct MessageBubble: View {
    @EnvironmentObject var store: AppStore
    let message: Message
    let conversation: Conversation?

    private var isUser: Bool { message.senderId == "user" }
    private var sender: Agent? { store.agent(id: UUID(uuidString: message.senderId) ?? UUID()) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 40) }
            if !isUser, let s = sender {
                AvatarDisc(text: s.initial, hue: s.tintHue, size: 30)
            }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                if !isUser, let s = sender, conversation?.isGroup == true {
                    Text(s.name).font(.caption).foregroundStyle(.secondary)
                }
                if let reasoning = message.reasoning, !reasoning.isEmpty {
                    DisclosureGroup("深度思考") {
                        Text(reasoning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 10))
                }
                Text(message.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(isUser ? Color.blue : Color(white: 0.15))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            if !isUser { Spacer(minLength: 40) }
        }
    }
}
