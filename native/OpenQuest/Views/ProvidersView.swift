import SwiftUI

/// 内置免费模型源（用户 2026-11-19 定的）：点一下添加，地址和模型都预填，
/// 用户只填自己的 Key 才算开启，不填就是关着。
struct ProviderPreset {
    let name: String
    let baseURL: String
    let models: [String]
    let note: String
}

let providerPresets: [ProviderPreset] = [
    ProviderPreset(name: "智谱 BigModel", baseURL: "https://open.bigmodel.cn/api/paas/v4",
                   models: ["glm-4-flash", "glm-4.5-flash"], note: "GLM-Flash 永久免费"),
    ProviderPreset(name: "Agnes", baseURL: "https://api.agnes-ai.cn/v1",
                   models: ["agnes-2.5-flash", "agnes-2.5-pro"], note: "免费额度"),
    ProviderPreset(name: "硅基流动", baseURL: "https://api.siliconflow.cn/v1",
                   models: ["Qwen/Qwen2.5-7B-Instruct"], note: "9B 以下小模型免费，需实名"),
    ProviderPreset(name: "魔搭 ModelScope", baseURL: "https://api-inference.modelscope.cn/v1",
                   models: ["Qwen/Qwen2.5-7B-Instruct"], note: "每日约 2000 次免费"),
]

/// 供应商与模型：用户自己添加供应商（名字、接口地址、Key），
/// 再往供应商下面添加模型。建智能体时从这些模型里选。
struct ProvidersView: View {
    @EnvironmentObject var store: AppStore
    @State private var showingAdd = false

    var body: some View {
        List {
            Section("免费源（点一下添加，填 Key 就能用）") {
                ForEach(providerPresets, id: \.name) { preset in
                    Button {
                        store.addPresetProvider(name: preset.name, baseURL: preset.baseURL,
                                                modelIds: preset.models)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name).foregroundStyle(.primary)
                                Text(preset.note).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.providers.contains(where: { $0.baseURL == preset.baseURL }) {
                                Image(systemName: "checkmark").foregroundStyle(.green)
                            } else {
                                Image(systemName: "plus.circle").foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
            ForEach(store.providers) { p in
                Section {
                    KeyRow(provider: p)
                    HeadersRow(provider: p)
                    FetchModelsRow(providerId: p.id)
                    ForEach(p.models) { m in
                        Text(m.name)
                    }
                    .onDelete { idx in
                        for i in idx { store.deleteModel(providerId: p.id, modelId: p.models[i].id) }
                    }
                    AddModelRow(providerId: p.id)
                } header: {
                    HStack {
                        Text(p.name)
                        Spacer()
                        Text(p.baseURL).font(.caption2).foregroundStyle(.secondary)
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
                    .foregroundStyle(n == 0 ? .secondary : .green)
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
            TextField("添加模型 id，如 agnes-2.5-flash", text: $modelId)
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

    var body: some View {
        NavigationStack {
            Form {
                TextField("供应商名字，如 Agnes", text: $name)
                TextField("接口地址，如 https://api.agnes-ai.cn/v1", text: $baseURL)
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
                            apiKey: apiKey.trimmingCharacters(in: .whitespaces)
                        )
                        dismiss()
                    }
                    .disabled(name.isEmpty || baseURL.isEmpty)
                }
            }
        }
    }
}
