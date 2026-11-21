import SwiftUI
import UniformTypeIdentifiers

// MARK: - Data controls

/// 数据控制: what the agent may learn from, import/export of the user's
/// own data, and the full reset (Start over). Training is never on: the
/// user's conversations are never used for training.
struct DataControlsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingImporter = false
    @State private var importResult: String?
    @State private var showingExporter = false
    @State private var exportURL: URL?
    @State private var confirmReset = false

    var body: some View {
        List {
            Section {
                HStack {
                    Text(L("用我的对话训练模型"))
                    Spacer()
                    Text(L("永不"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.secondary)
                }
            } header: {
                Text(L("训练"))
            } footer: {
                Text(L("你的对话绝不会被用来训练模型。"))
            }
            Section {
                Button {
                    showingImporter = true
                } label: {
                    Label(L("导入记忆（.md 文件）"), systemImage: "square.and.arrow.down")
                }
                Button {
                    exportData()
                } label: {
                    Label(L("下载你的数据"), systemImage: "square.and.arrow.up")
                }
                if let importResult {
                    Text(importResult)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondary)
                }
            } header: {
                Text(L("你的数据"))
            } footer: {
                Text(L("导入的 .md 会追加进 Memory；下载会打包 Soul、Memory、Identity、目标和审核记录。"))
            }
            Section {
                Button(role: .destructive) {
                    confirmReset = true
                } label: {
                    Label(L("重置并重新开始"), systemImage: "arrow.counterclockwise")
                }
            } footer: {
                Text(L("会退出账号、忘记全部电脑并清空本地数据，回到欢迎页。"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("数据控制"))
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [UTType(filenameExtension: "md") ?? .plainText]
        ) { result in
            switch result {
            case .success(let url):
                importMemory(from: url)
            case .failure:
                importResult = L("导入失败，请重试。")
            }
        }
        .codyncSheet(isPresented: $showingExporter) {
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label(L("分享导出文件"), systemImage: "square.and.arrow.up")
                }
                .presentationDetents([.medium])
            }
        }
        .codyncDialog(
            isPresented: $confirmReset,
            title: L("重置并重新开始？"),
            message: L("会退出账号、忘记全部电脑并清空本地数据，回到欢迎页。这个操作无法撤销。"),
            actions: [
                CodyncDialogAction(title: L("取消")) {},
                CodyncDialogAction(title: L("重置"), isDestructive: true) {
                    Task { await store.startOver() }
                },
            ]
        )
    }

    private func importMemory(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importResult = L("导入失败，请重试。")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
            importResult = L("这个文件是空的，或者读不出来。")
            return
        }
        store.identity.appendToMemory(text)
        importResult = L("已追加进 Memory。")
    }

    private func exportData() {
        let date = DateFormatter.dataExport.string(from: Date())
        var parts: [String] = []
        parts.append("# Soul\n\n\(store.identity.soul)")
        parts.append("# Memory\n\n\(store.identity.memory)")
        parts.append("# Identity\n\n\(store.identity.identity)")
        parts.append("# 目标\n")
        for goal in store.goals.goals {
            parts.append("- [\(goal.completed ? "x" : " ")] \(goal.title)（\(GoalCategory(rawValue: goal.type)?.label ?? goal.type)）")
        }
        parts.append("# 审核记录\n")
        for record in store.audit.records {
            parts.append("- \(DateFormatter.auditTime.string(from: record.date)) \(record.botName)：\(record.title)")
        }
        let text = parts.joined(separator: "\n\n")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lingyu-data-\(date).md")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        exportURL = url
        showingExporter = true
    }
}

private extension DateFormatter {
    static let dataExport: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return f
    }()
}

// MARK: - Credential vault

/// 安全凭证库: the user's own logins, kept in the keychain. Each login
/// says whether an agent may use it directly ("直接使用") or must ask
/// first ("每次询问"). The password itself is never shown in the list.
struct CredentialVaultView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: VaultLogin?
    @State private var adding = false

    var body: some View {
        List {
            if store.vault.logins.isEmpty {
                Text(L("还没有保存任何账号。密码只存在本机钥匙串里，不会上传。"))
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
            }
            ForEach(store.vault.logins) { login in
                Button {
                    editing = login
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(login.title)
                                .font(.body)
                                .foregroundStyle(Palette.text)
                            Text(login.username)
                                .font(.subheadline)
                                .foregroundStyle(Palette.secondary)
                        }
                        Spacer()
                        Text(login.agentPermission == "auto" ? L("直接使用") : L("每次询问"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    store.vault.delete(id: store.vault.logins[index].id)
                }
            }
            Section {
                Button {
                    adding = true
                } label: {
                    Label(L("添加账号"), systemImage: "plus")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("安全凭证库"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
                    .disabled(store.vault.logins.isEmpty)
            }
        }
        .codyncSheet(isPresented: $adding) {
            NavigationStack { VaultLoginEditor(login: nil) }
        }
        .codyncSheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            if let login = editing {
                NavigationStack { VaultLoginEditor(login: login) }
            }
        }
    }
}

struct VaultLoginEditor: View {
    var login: VaultLogin?
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var username = ""
    @State private var password = ""
    @State private var permission = "ask"

    var body: some View {
        List {
            Section {
                TextField(L("名称"), text: $title)
                TextField(L("用户名"), text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(L("密码"), text: $password)
            } header: {
                Text(L("账号"))
            } footer: {
                Text(login == nil ? L("密码只存进本机钥匙串，不会上传。") : L("密码留空表示不改。"))
            }
            Section {
                ChoicePicker(selection: $permission, options: [
                    ("ask", L("每次询问")),
                    ("auto", L("直接使用")),
                ])
            } header: {
                Text(L("智能体使用"))
            } footer: {
                Text(L("「直接使用」表示智能体可以直接用这个账号登录；「每次询问」表示每次使用前都要你批准。"))
            }
            if let login {
                Section {
                    Button(role: .destructive) {
                        store.vault.delete(id: login.id)
                        dismiss()
                    } label: {
                        Text(L("删除这个账号"))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(login == nil ? L("添加账号") : L("编辑账号"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("保存")) {
                    if let login {
                        store.vault.update(id: login.id, title: title, username: username,
                                           password: password.isEmpty ? nil : password, permission: permission)
                    } else {
                        store.vault.add(title: title, username: username, password: password, permission: permission)
                    }
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || (login == nil && password.isEmpty))
            }
        }
        .onAppear {
            title = login?.title ?? ""
            username = login?.username ?? ""
            permission = login?.agentPermission ?? "ask"
        }
    }
}

// MARK: - Network protocols

/// 网络协议屏: which network abilities agents may use, plus the DNS
/// setting. Every protocol defaults to Deny and has no Allow option.
/// The screen states plainly that the host does not enforce these yet.
struct NetworkProtocolsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        List {
            Section {
                ForEach(NetworkPrefs.protocols, id: \.key) { proto in
                    HStack {
                        Text(L(proto.label))
                        Spacer()
                        ChoicePicker(selection: binding(for: proto.key), options: [
                            ("deny", L("拒绝")),
                            ("ask", L("询问")),
                        ])
                    }
                }
            } header: {
                Text(L("网络协议"))
            } footer: {
                Text(L("默认全部拒绝。需要用到某个协议时，智能体会先问你。电脑端尚未读取这些设置，当前仅保存在本机。"))
            }
            Section {
                ForEach(NetworkPrefs.dnsModes, id: \.key) { mode in
                    HStack {
                        Text(L(mode.label))
                        Spacer()
                        if store.network.dnsMode == mode.key {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Palette.accent)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { store.network.dnsMode = mode.key }
                }
                if store.network.dnsMode == "custom" {
                    TextField(L("自定义 DNS 地址，如 223.5.5.5"), text: Binding(
                        get: { store.network.customDNS },
                        set: { store.network.customDNS = $0 }
                    ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.decimalPad)
                }
                if let address = store.network.dnsAddress {
                    Text(L("当前地址") + "：" + address)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondary)
                }
            } header: {
                Text(L("DNS"))
            } footer: {
                Text(L("默认跟随系统。国内 DNS 预设：阿里、腾讯、114。"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("网络协议"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Explicit get/set bindings: `network` is a `let` on the store, so
    /// `$store.network.<prop>` (which needs a writable key path) does not
    /// compile.
    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { self.value(for: key) },
            set: { self.setValue($0, for: key) }
        )
    }

    private func value(for key: String) -> String {
        switch key {
        case "ssh": return store.network.ssh
        case "emailSend": return store.network.emailSend
        case "mailbox": return store.network.mailbox
        case "database": return store.network.database
        case "ftp": return store.network.ftp
        case "externalDNS": return store.network.externalDNS
        default: return store.network.tcpUdp
        }
    }

    private func setValue(_ value: String, for key: String) {
        switch key {
        case "ssh": store.network.ssh = value
        case "emailSend": store.network.emailSend = value
        case "mailbox": store.network.mailbox = value
        case "database": store.network.database = value
        case "ftp": store.network.ftp = value
        case "externalDNS": store.network.externalDNS = value
        default: store.network.tcpUdp = value
        }
    }
}
