import SwiftUI

/// 环境变量页（Minis `EnvVarStore`，Shared/EnvVarStore.swift：
/// key/note/开关进快照，值是秘密、另存 Keychain）。
/// 智能体工具调用（shell/脚本）时，把启用的变量注入进去。
struct EnvVarsView: View {
    @EnvironmentObject var store: AppStore
    @State private var showingAdd = false

    var body: some View {
        List {
            if store.envVars.isEmpty {
                Text("还没有环境变量。点右上角加一个：名字（如 API_BASE_URL）和值填好，智能体跑 shell、脚本时就能用；值只存系统钥匙串，不落盘到普通文件。")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.envVars) { v in
                NavigationLink {
                    EnvVarDetailView(envVarId: v.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(v.key).font(.body.monospaced())
                            if !v.enabled {
                                Text("已停用").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 8) {
                            if !v.note.isEmpty {
                                Text(v.note).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(store.envVarValue(id: v.id).isEmpty ? "值未填" : "值已填")
                                .font(.caption)
                                .foregroundStyle(store.envVarValue(id: v.id).isEmpty ? .orange : .green)
                        }
                    }
                }
            }
            .onDelete { idx in
                for i in idx { store.deleteEnvVar(id: store.envVars[i].id) }
            }
            Section {
                Text("注入规则：只注入「已启用」且「值已填」的变量；工具调用、命令里不会把值打印出来。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("环境变量")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) { AddEnvVarView() }
    }
}

private struct AddEnvVarView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var key = ""
    @State private var note = ""
    @State private var value = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("变量名，如 API_BASE_URL", text: $key)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("值（存系统钥匙串）", text: $value)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("说明（可空，如：给翻译脚本用的接口地址）", text: $note)
            }
            .navigationTitle("新建环境变量")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.addEnvVar(key: key.trimmingCharacters(in: .whitespaces),
                                        note: note.trimmingCharacters(in: .whitespaces),
                                        value: value)
                        dismiss()
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

private struct EnvVarDetailView: View {
    @EnvironmentObject var store: AppStore
    let envVarId: UUID
    @State private var key = ""
    @State private var note = ""
    @State private var value = ""
    @State private var savedNote: String?

    private var envVar: EnvVar? { store.envVars.first { $0.id == envVarId } }

    var body: some View {
        Form {
            if let v = envVar {
                Section("开关") {
                    Toggle("启用这个变量", isOn: Binding(
                        get: { v.enabled },
                        set: { store.setEnvVarEnabled(id: v.id, $0) }
                    ))
                    Text("关掉后工具调用时不注入，值留着，下次打开接着用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("名字与说明") {
                    TextField("变量名", text: $key)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("说明（可空）", text: $note)
                }
                Section("值") {
                    SecureField("值（存系统钥匙串）", text: $value)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Text("值只存你手机的系统钥匙串里，不上传、不落盘到普通文件。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("保存") {
                        store.updateEnvVar(id: v.id,
                                           key: key.trimmingCharacters(in: .whitespaces),
                                           note: note.trimmingCharacters(in: .whitespaces))
                        store.setEnvVarValue(id: v.id, value: value)
                        savedNote = "已保存"
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let savedNote {
                        Text(savedNote).font(.caption).foregroundStyle(.green)
                    }
                }
            }
        }
        .navigationTitle(envVar?.key ?? "环境变量")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            key = envVar?.key ?? ""
            note = envVar?.note ?? ""
            value = store.envVarValue(id: envVarId)
        }
    }
}
