import SwiftUI

/// 群设置（FishPocket 式）：群主、发言模式、群公告、群目标、成员停下/恢复。
struct GroupSettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let conversationId: UUID
    @State private var addMemberId: UUID?

    private var conv: Conversation? {
        store.conversations.first { $0.id == conversationId }
    }

    /// 能加进群的智能体：不在群里、不是私有的。
    private func addableAgents(for c: Conversation) -> [Agent] {
        store.agents.filter { !c.memberIds.contains($0.id) && !$0.isPrivate }
    }

    /// 移出成员：群主被移走时群主位空出来（发言模式照常，群主没了就按轮流接话，
    /// 上面会提示重新选群主）；被停下的成员一并从停下名单里清掉。
    private func removeMember(_ id: UUID) {
        setConv { conv in
            conv.memberIds.removeAll { $0 == id }
            conv.stoppedMembers.removeAll { $0 == id }
            if conv.adminId == id { conv.adminId = nil }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let c = conv {
                    Section("群名") {
                        TextField("群名", text: convBinding(\.title))
                    }
                    Section("发言") {
                        Picker("发言模式", selection: convBinding(\.speakMode)) {
                            Text("全员轮流").tag("everyone")
                            Text("群主先接，再点名").tag("admin")
                        }
                        .pickerStyle(.segmented)
                        Picker("群主", selection: convBinding(\.adminId)) {
                            Text("不设群主").tag(nil as UUID?)
                            ForEach(c.memberIds.compactMap { store.agent(id: $0) }) { a in
                                Text(a.name).tag(a.id as UUID?)
                            }
                        }
                        Text(c.speakMode == "admin"
                             ? "用户消息先给群主；群主回复里 @ 谁，谁接着说；群主没点名就停下。"
                             : "每条消息群里智能体轮流回复。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("群公告") {
                        TextEditor(text: convBinding(\.notice))
                            .frame(minHeight: 70)
                            .onChange(of: c.notice) { _, v in
                                if v.count > 2000 { setConv { $0.notice = String(v.prefix(2000)) } }
                            }
                        HStack {
                            Text("每个成员发言前都会先读这段公告。")
                            Spacer()
                            Text("\(c.notice.count)/2000 字")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("群目标") {
                        TextField("目标标题，如：做一份产品测评", text: convBinding(\.goalTitle))
                        if !c.goalStages.isEmpty {
                            Stepper("当前阶段：\(c.goalCurrent + 1) / \(c.goalStages.count)",
                                    value: Binding(
                                        get: { c.goalCurrent },
                                        set: { v in
                                            setConv { $0.goalCurrent = min(max(v, 0), max(c.goalStages.count - 1, 0)) }
                                        }
                                    ), in: 0...max(c.goalStages.count - 1, 0))
                        }
                        ForEach(c.goalStages, id: \.self) { stage in
                            Text(stage)
                        }
                        .onDelete { idx in
                            setConv { $0.goalStages.remove(atOffsets: idx) }
                        }
                        GoalStageRow(onAdd: { stage in
                            setConv { $0.goalStages.append(stage) }
                        })
                        Picker("状态", selection: convBinding(\.goalStatus)) {
                            Text("进行中").tag("active")
                            Text("已完成").tag("done")
                            Text("已停下").tag("stopped")
                        }
                        .pickerStyle(.segmented)
                    }
                    Section("成员（\(c.memberIds.count)/12 人）") {
                        ForEach(c.memberIds.compactMap { store.agent(id: $0) }) { a in
                            HStack {
                                AvatarDisc(text: a.initial, hue: a.tintHue, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(a.name)
                                    if c.adminId == a.id {
                                        Text("群主").font(.caption).foregroundStyle(.orange)
                                    } else if c.stoppedMembers.contains(a.id) {
                                        Text("已停下").font(.caption).foregroundStyle(.red)
                                    }
                                }
                                Spacer()
                                Button(c.stoppedMembers.contains(a.id) ? "恢复" : "停下") {
                                    setConv { conv in
                                        if conv.stoppedMembers.contains(a.id) {
                                            conv.stoppedMembers.removeAll { $0 == a.id }
                                        } else {
                                            conv.stoppedMembers.append(a.id)
                                        }
                                    }
                                }
                                .font(.subheadline)
                                Button("移出", role: .destructive) {
                                    removeMember(a.id)
                                }
                                .font(.subheadline)
                                .disabled(c.memberIds.count <= 2)
                            }
                        }
                        if c.memberIds.count <= 2 {
                            Text("群最少 2 人，再移就只剩一个人了。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if c.memberIds.count >= 12 {
                            Text("群最多 12 人，已经满了。")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Picker("加成员", selection: $addMemberId) {
                                Text("选一个加进来").tag(nil as UUID?)
                                ForEach(addableAgents(for: c)) { a in
                                    Text(a.name).tag(a.id as UUID?)
                                }
                            }
                            .onChange(of: addMemberId) { _, v in
                                guard let v else { return }
                                setConv { $0.memberIds.append(v) }
                                addMemberId = nil
                            }
                            Text("私有智能体只能单聊，不能加进群。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if c.adminId != nil, !c.memberIds.contains(c.adminId!) {
                            Text("群主已不在群里，先在上面重新选一个群主，不然群主模式会按轮流接话。")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        HStack {
                            Button("全部停下") {
                                setConv { $0.stoppedMembers = c.memberIds }
                            }
                            .foregroundStyle(.red)
                            Spacer()
                            Button("全部恢复") {
                                setConv { $0.stoppedMembers = [] }
                            }
                        }
                    }
                }
            }
            .navigationTitle("群设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    /// 会话字段的双向绑定：读 store 里最新的，写回 store 并落盘。
    private func convBinding<T>(_ keyPath: WritableKeyPath<Conversation, T>) -> Binding<T> {
        Binding(
            get: { store.conversations.first { $0.id == conversationId }?[keyPath: keyPath]
                ?? Conversation(title: "")[keyPath: keyPath] },
            set: { newValue in
                guard let i = store.conversations.firstIndex(where: { $0.id == conversationId }) else { return }
                store.conversations[i][keyPath: keyPath] = newValue
                store.save()
            }
        )
    }

    /// 直接改会话（删阶段、停成员这类整段操作）。
    private func setConv(_ mutate: (inout Conversation) -> Void) {
        guard let i = store.conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        mutate(&store.conversations[i])
        store.save()
    }
}

private struct GoalStageRow: View {
    var onAdd: (String) -> Void
    @State private var text = ""

    var body: some View {
        HStack {
            TextField("加一个阶段，如：查价格", text: $text)
            Button("加") {
                let v = text.trimmingCharacters(in: .whitespaces)
                guard !v.isEmpty else { return }
                onAdd(v)
                text = ""
            }
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
