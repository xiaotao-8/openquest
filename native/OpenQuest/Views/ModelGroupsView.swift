import SwiftUI

/// 模型组详情（Minis `ModelGroup`，Providers/ModelGroup.swift:22-28；
/// 路由语义见 Providers/ModelGroupRouter.swift）：
/// 一个组内多个模型，主模型失败时按顺序兜底；组可在聊天里直接选用。
/// groupId 为 nil = 新建一组；否则编辑已有组。
struct ModelGroupDetailView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let groupId: UUID?

    @State private var name = ""
    @State private var memberRefs: [String] = []
    @State private var strategy = "fallback"
    @State private var fallbackStrategy = "limited"
    @State private var defaultThinkingLevel = ""

    private var group: ModelGroup? {
        guard let groupId else { return nil }
        return store.modelGroups.first { $0.id == groupId }
    }

    /// 全部可选成员：每个供应商下面的每个模型。
    private var allMembers: [(provider: ModelProvider, model: AIModel)] {
        store.providers.flatMap { p in p.models.map { (p, $0) } }
    }

    private var chosen: [(provider: ModelProvider, model: AIModel)] {
        ModelGroup(name: name, memberRefs: memberRefs).members(providers: store.providers)
    }

    var body: some View {
        Form {
            Section("名字") {
                TextField("组名，如：主力组", text: $name)
            }
            Section("成员（顺序就是兜底顺序，可拖动调顺序）") {
                if chosen.isEmpty {
                    Text("还没加模型，下面点一个加进来。")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(chosen.enumerated()), id: \.offset) { _, pair in
                    HStack {
                        Text(pair.model.name).foregroundStyle(.primary)
                        Spacer()
                        Text(pair.provider.name).font(.caption).foregroundStyle(.secondary)
                        Button {
                            memberRefs.removeAll {
                                $0 == ModelGroup.ref(providerId: pair.provider.id, modelId: pair.model.id)
                            }
                        } label: {
                            Image(systemName: "minus.circle").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onMove { from, to in memberRefs.move(fromOffsets: from, toOffset: to) }
            }
            Section("再加一个模型") {
                if allMembers.isEmpty {
                    Text("先去供应商页加供应商和模型，这里才能组。")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(allMembers.enumerated()), id: \.offset) { _, pair in
                    let ref = ModelGroup.ref(providerId: pair.provider.id, modelId: pair.model.id)
                    Button {
                        if !memberRefs.contains(ref) { memberRefs.append(ref) }
                    } label: {
                        HStack {
                            Text(pair.model.name).foregroundStyle(.primary)
                            Spacer()
                            Text(pair.provider.name).font(.caption).foregroundStyle(.secondary)
                            if memberRefs.contains(ref) {
                                Image(systemName: "checkmark").foregroundStyle(.green)
                            } else {
                                Image(systemName: "plus.circle").foregroundStyle(.blue)
                            }
                        }
                    }
                    .disabled(memberRefs.contains(ref))
                }
            }
            Section("路由") {
                Picker("策略", selection: $strategy) {
                    Text("按顺序兜底").tag("fallback")
                    Text("按会话分流").tag("loadBalance")
                }
                Picker("什么时候兜底", selection: $fallbackStrategy) {
                    Text("只在供应商级错误时").tag("limited")
                    Text("任何错误都兜底").tag("always")
                }
                Text(strategy == "loadBalance"
                     ? "按会话分流：同一个会话固定走组里同一个模型，不同会话分到不同模型。"
                     : "按顺序兜底：先走第一个模型，失败（限流、Key 失效、供应商拒绝）再走下一个；「任何错误都兜底」连网络错误也不在当前模型上重试，直接换下一个。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("组默认思考档位") {
                Picker("思考档位", selection: $defaultThinkingLevel) {
                    ForEach(ThinkingLevel.allOptions, id: \.self) { opt in
                        Text(ThinkingLevel.label(for: opt)).tag(opt)
                    }
                }
                .pickerStyle(.navigationLink)
                Text("组里新会话的默认档位；智能体或模型自己设了档位时，以它们自己的为准。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(group == nil ? "新建模型组" : (group?.name ?? "模型组"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { saveAndClose() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            if let g = group {
                name = g.name
                memberRefs = g.memberRefs
                strategy = g.strategy
                fallbackStrategy = g.fallbackStrategy
                defaultThinkingLevel = g.defaultThinkingLevel
            }
        }
    }

    private func saveAndClose() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let g = group {
            var updated = g
            updated.name = trimmed
            updated.memberRefs = memberRefs
            updated.strategy = strategy
            updated.fallbackStrategy = fallbackStrategy
            updated.defaultThinkingLevel = defaultThinkingLevel
            store.updateModelGroup(updated)
        } else {
            var g = ModelGroup(name: trimmed, memberRefs: memberRefs)
            g.strategy = strategy
            g.fallbackStrategy = fallbackStrategy
            g.defaultThinkingLevel = defaultThinkingLevel
            store.modelGroups.append(g)
            store.save()
        }
        dismiss()
    }
}
