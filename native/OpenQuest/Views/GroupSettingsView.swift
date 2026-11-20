import SwiftUI

/// 群设置（FishPocket 式）：群主、发言模式、群公告、群目标、成员停下/恢复。
struct GroupSettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let conversationId: UUID

    private var conv: Conversation? {
        store.conversations.first { $0.id == conversationId }
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
                        Text("每个成员发言前都会先读这段公告。")
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
                    Section("成员") {
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
                            }
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
