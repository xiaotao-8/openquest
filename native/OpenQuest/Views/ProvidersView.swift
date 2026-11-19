import SwiftUI

/// 供应商与模型：用户自己添加供应商（名字、接口地址、Key），
/// 再往供应商下面添加模型。建智能体时从这些模型里选。
struct ProvidersView: View {
    @EnvironmentObject var store: AppStore
    @State private var showingAdd = false

    var body: some View {
        List {
            if store.providers.isEmpty {
                Text("还没有供应商。点右上角添加：填名字、接口地址和你的 Key。")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.providers) { p in
                Section {
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
