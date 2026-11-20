import SwiftUI

/// 模型切换器（DDchat 式）：按供应商分组的玻璃 bottom sheet + 思考档位滑条。
/// 在聊天页右上角打开，点模型就换；档位存在智能体身上（effort）。
struct ModelPickerSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let agent: Agent
    @State private var showingProviders = false

    private var effort: String { agent.effort }

    var body: some View {
        NavigationStack {
            List {
                // 思考档位只在模型支持深度思考时显示（能力自动检测；没检测出按支持处理）。
                if store.agentSupportsReasoning(agent) {
                    Section("思考档位") {
                        Picker("思考档位", selection: Binding(
                            get: { effort },
                            set: { store.setAgentEffort(agentId: agent.id, effort: $0) }
                        )) {
                            ForEach(ThinkingLevel.allOptions, id: \.self) { opt in
                                Text(ThinkingLevel.label(for: opt)).tag(opt)
                            }
                        }
                        .pickerStyle(.menu)
                        Text("档位越高想得越深、回得越慢；关就是不让模型做深度思考。档位按六档：低/中/高/超高/最高分别发 low/medium/high/xhigh/max。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !store.modelGroups.isEmpty {
                    Section("模型组（主模型失败时按顺序兜底）") {
                        ForEach(store.modelGroups) { g in
                            Button {
                                store.setAgentModelGroup(agentId: agent.id, group: g)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(g.name).foregroundStyle(.primary)
                                        Text(g.members(providers: store.providers)
                                            .map { $0.model.name }.joined(separator: " → "))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if agent.modelGroupId == g.id.uuidString {
                                        Image(systemName: "checkmark").foregroundStyle(.green)
                                    }
                                }
                            }
                        }
                        if let g = store.modelGroup(for: agent) {
                            Text("当前走组「\(g.name)」：先用组里第一个模型，失败按顺序兜底。点下面单个模型就改回单模型。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(store.providers) { p in
                    Section(p.name) {
                        if p.models.isEmpty {
                            Text("这个供应商下面还没模型")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(p.models) { m in
                            Button {
                                store.setAgentModel(agentId: agent.id, provider: p, modelId: m.id)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(m.name).foregroundStyle(.primary)
                                    Spacer()
                                    if agent.providerKey == p.id.uuidString && agent.modelId == m.id {
                                        Image(systemName: "checkmark").foregroundStyle(.green)
                                    }
                                }
                            }
                        }
                    }
                }
                Section {
                    Button {
                        showingProviders = true
                    } label: {
                        Label("添加供应商", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("换模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(36)
        .sheet(isPresented: $showingProviders) {
            NavigationStack { ProvidersView() }
        }
    }
}
