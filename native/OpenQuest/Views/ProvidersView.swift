import SwiftUI

/// 供应商与模型：用户自己添加供应商（名字、接口地址、Key），
/// 再往供应商下面添加模型。建智能体时从这些模型里选。
/// 不预置任何供应商和模型（用户 2026-11-20 撤了免费源预设，全由用户自己填）。
struct ProvidersView: View {
    @EnvironmentObject var store: AppStore
    @State private var showingAdd = false

    var body: some View {
        List {
            Section("模型组（主模型失败时按顺序兜底）") {
                ForEach(store.modelGroups) { g in
                    NavigationLink {
                        ModelGroupDetailView(groupId: g.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.name).foregroundStyle(.primary)
                                Text(g.memberRefs.isEmpty ? "还没加模型" : "\(g.members(providers: store.providers).count) 个模型 · \(g.strategy == "loadBalance" ? "按会话分流" : "按顺序兜底")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
                .onDelete { idx in
                    for i in idx { store.deleteModelGroup(id: store.modelGroups[i].id) }
                }
                NavigationLink {
                    ModelGroupDetailView(groupId: nil)
                } label: {
                    Label("新建模型组", systemImage: "plus.circle")
                }
            }
            ForEach(store.providers) { p in
                Section {
                    KeyRow(provider: p)
                    HeadersRow(provider: p)
                    FetchModelsRow(providerId: p.id)
                    ForEach(p.models) { m in
                        NavigationLink {
                            ModelEditView(providerId: p.id, modelId: m.id)
                        } label: {
                            HStack {
                                Text(m.name).foregroundStyle(.primary)
                                Spacer()
                                Text(ThinkingLevel.label(for: m.effort))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { idx in
                        for i in idx { store.deleteModel(providerId: p.id, modelId: p.models[i].id) }
                    }
                    AddModelRow(providerId: p.id)
                } header: {
                    HStack {
                        Text(p.name)
                        Text(p.kind.label).font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text(p.baseURL).font(.caption2).foregroundStyle(.secondary)
                        EditProviderButton(provider: p)
                    }
                }
            }
            .onDelete { idx in
                for i in idx { store.deleteProvider(id: store.providers[i].id) }
            }
        }
        .navigationTitle("供应商与模型")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) { AddProviderView() }
    }
}

/// 自动拉模型列表行：点一下从供应商接口把模型都拉回来，不用手填。
private struct FetchModelsRow: View {
    @EnvironmentObject var store: AppStore
    let providerId: UUID
    @State private var busy = false
    @State private var status: String?

    var body: some View {
        Button {
            busy = true
            Task {
                status = await store.fetchModels(providerId: providerId)
                busy = false
            }
        } label: {
            HStack {
                Text("自动获取模型列表").foregroundStyle(.primary)
                Spacer()
                if busy {
                    ProgressView()
                } else if let status {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .disabled(busy)
    }
}

/// 自定义请求头行（DDchat）：每行一个 "Key: Value"，该供应商的每次请求都带上；
/// 没冒号、键或值为空的行直接忽略。Authorization 和 Content-Type 归 App 管，不让改。
private struct HeadersRow: View {
    @EnvironmentObject var store: AppStore
    let provider: ModelProvider
    @State private var showingEdit = false
    @State private var headersText = ""

    var body: some View {
        Button {
            headersText = provider.customHeaders
            showingEdit = true
        } label: {
            HStack {
                Text("自定义请求头").foregroundStyle(.primary)
                Spacer()
                let n = provider.parsedCustomHeaders.count
                Text(n == 0 ? "未填" : "\(n) 个")
                    .foregroundStyle(n == 0 ? Color.secondary : Color.green)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                Form {
                    TextEditor(text: $headersText)
                        .frame(minHeight: 160)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Text("每行一个请求头，格式「Key: Value」，例如：\nX-Custom-Header: abc123\n没冒号、键或值为空的行直接忽略；Authorization 和 Content-Type 不用填，App 自己带。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .navigationTitle("\(provider.name) 的请求头")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showingEdit = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            store.setProviderHeaders(id: provider.id, headers: headersText)
                            showingEdit = false
                        }
                    }
                }
            }
        }
    }
}

/// 供应商的 Key 行：显示填没填，点开填/改（存系统钥匙串）。
private struct KeyRow: View {
    @EnvironmentObject var store: AppStore
    let provider: ModelProvider
    @State private var showingEdit = false
    @State private var keyText = ""

    var body: some View {
        Button { showingEdit = true } label: {
            HStack {
                Text("API Key").foregroundStyle(.primary)
                Spacer()
                Text(store.providerHasKey(provider) ? "已填" : "未填")
                    .foregroundStyle(store.providerHasKey(provider) ? .green : .orange)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                Form {
                    SecureField("粘贴 API Key", text: $keyText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Text("Key 只存你手机的系统钥匙串里，不上传、不落盘到普通文件。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .navigationTitle("\(provider.name) 的 Key")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showingEdit = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            store.setProviderKey(id: provider.id,
                                                 apiKey: keyText.trimmingCharacters(in: .whitespaces))
                            keyText = ""
                            showingEdit = false
                        }
                        .disabled(keyText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }
}

private struct AddModelRow: View {
    @EnvironmentObject var store: AppStore
    let providerId: UUID
    @State private var modelId = ""

    var body: some View {
        HStack {
            TextField("添加模型 id，如 deepseek-chat", text: $modelId)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("添加") {
                let v = modelId.trimmingCharacters(in: .whitespaces)
                guard !v.isEmpty else { return }
                store.addModel(providerId: providerId, modelId: v)
                modelId = ""
            }
            .disabled(modelId.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

private struct AddProviderView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var kind: ProviderKind = .openai

    var body: some View {
        NavigationStack {
            Form {
                TextField("供应商名字，如：我的供应商", text: $name)
                Picker("类型", selection: $kind) {
                    ForEach(ProviderKind.allCases, id: \.self) { k in
                        Text(k.label).tag(k)
                    }
                }
                Text("类型只定接口格式：OpenAI 兼容按 OpenAI chat completions 格式发请求，地址缺 /v1 时自动补上。")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("接口地址，如 https://api.example.com/v1", text: $baseURL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                SecureField("API Key（存系统钥匙串）", text: $apiKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .navigationTitle("添加供应商")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.addProvider(
                            name: name.trimmingCharacters(in: .whitespaces),
                            baseURL: baseURL.trimmingCharacters(in: .whitespaces),
                            apiKey: apiKey.trimmingCharacters(in: .whitespaces),
                            kind: kind
                        )
                        dismiss()
                    }
                    .disabled(name.isEmpty || baseURL.isEmpty)
                }
            }
        }
    }
}

/// 供应商改名/改地址（Key 不动，仍在 Keychain 里；删供应商走列表左滑删除）。
private struct EditProviderButton: View {
    let provider: ModelProvider
    @State private var showingEdit = false

    var body: some View {
        Button {
            showingEdit = true
        } label: {
            Image(systemName: "pencil")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingEdit) {
            EditProviderView(provider: provider)
        }
    }
}

private struct EditProviderView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let provider: ModelProvider
    @State private var name = ""
    @State private var baseURL = ""
    @State private var kind: ProviderKind = .openai

    var body: some View {
        NavigationStack {
            Form {
                TextField("供应商名字", text: $name)
                Picker("类型", selection: $kind) {
                    ForEach(ProviderKind.allCases, id: \.self) { k in
                        Text(k.label).tag(k)
                    }
                }
                TextField("接口地址，如 https://api.example.com/v1", text: $baseURL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                Text("Key 不在这里改，上一页的「API Key」行里改；Key 只存系统钥匙串。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("改供应商")
            .onAppear {
                name = provider.name
                baseURL = provider.baseURL
                kind = provider.kind
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.updateProvider(id: provider.id,
                                             name: name.trimmingCharacters(in: .whitespaces),
                                             baseURL: baseURL.trimmingCharacters(in: .whitespaces),
                                             kind: kind)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                              || baseURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// 模型详情：显示名 + 每模型的思考档位（Minis ThinkingLevel：
/// 跟模型默认 / 关 / 低 / 中 / 高 / 超高 / 最高），存进模型配置。
/// 智能体没单独设档位时就用这里的；两个都没设跟模型默认。
private struct ModelEditView: View {
    @EnvironmentObject var store: AppStore
    let providerId: UUID
    let modelId: String
    @State private var displayName = ""
    @State private var effort = ""

    private var model: AIModel? {
        store.providers.first { $0.id == providerId }?
            .models.first { $0.id == modelId }
    }

    var body: some View {
        Form {
            Section("模型") {
                Text(model?.id ?? modelId)
                    .font(.subheadline).foregroundStyle(.secondary)
                TextField("显示名（空着就用模型 id）", text: $displayName)
            }
            Section("思考档位") {
                Picker("思考档位", selection: $effort) {
                    ForEach(ThinkingLevel.allOptions, id: \.self) { opt in
                        Text(ThinkingLevel.label(for: opt)).tag(opt)
                    }
                }
                .pickerStyle(.navigationLink)
                Text("档位越高想得越深、回得越慢；「关」就是不让模型做深度思考。发给模型的值：低/中/高/超高/最高分别发 low/medium/high/xhigh/max。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text("能力自动检测：深度思考 \(model?.supportsReasoning.map { $0 ? "支持" : "不支持" } ?? "未检测出，按支持处理")，视觉 \(model?.supportsVision.map { $0 ? "支持" : "不支持" } ?? "未检测出，按支持处理")。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(model?.name ?? "模型")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            displayName = model?.displayName ?? ""
            effort = model?.effort ?? ""
        }
        .onChange(of: displayName) { _, v in save() }
        .onChange(of: effort) { _, v in save() }
    }

    private func save() {
        store.updateModel(providerId: providerId, modelId: modelId,
                          displayName: displayName.trimmingCharacters(in: .whitespaces),
                          effort: effort)
    }
}
