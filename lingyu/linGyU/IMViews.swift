import SwiftUI
import Security

/// IM 桥接:把飞书、钉钉、Slack 的消息接给一个智能体回。
///
/// Live probe on host 2.51.0 (2026-11-22, probe_p4h.py): the host has no IM
/// methods at all (`imList` / `imConnections` both answer 404 unknown
/// method; the source has no feishu / dingtalk / weixin / wecom code, and
/// slack appears only as a routine event source). So this page never claims
/// a connection is live: saving stores the credentials on this phone only
/// (secrets in the keychain, the rest in UserDefaults) and the status line
/// always says the bridge engine is not connected. Pairing approval
/// (`im-pair` / `im-unpair`) and per-conversation reassignment have no host
/// method either, so they are shown disabled with the reason. WeChat QR
/// login is undecided for Phase 4 and is not built.
struct IMBridgeView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var connections: [IMConnection] = IMConnectionStore.load()
    @State private var feishuAppId = ""
    @State private var feishuSecret = ""
    @State private var feishuBotId = ""
    @State private var feishuError: String?
    @State private var dingtalkClientId = ""
    @State private var dingtalkSecret = ""
    @State private var dingtalkBotId = ""
    @State private var dingtalkError: String?
    @State private var slackAppToken = ""
    @State private var slackBotToken = ""
    @State private var slackBotId = ""
    @State private var slackError: String?
    @State private var showingComputerUse = false
    @State private var showingBotImport = false

    private var bots: [Bot] {
        store.connector.mirror.bots.filter { !$0.isGroup }
    }

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("IM 桥接")) {
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusSection
                    platformCard(
                        platform: "feishu",
                        field1: $feishuAppId, field2: $feishuSecret, botId: $feishuBotId,
                        error: $feishuError
                    )
                    platformCard(
                        platform: "dingtalk",
                        field1: $dingtalkClientId, field2: $dingtalkSecret, botId: $dingtalkBotId,
                        error: $dingtalkError
                    )
                    platformCard(
                        platform: "slack",
                        field1: $slackAppToken, field2: $slackBotToken, botId: $slackBotId,
                        error: $slackError
                    )
                    pairingSection
                    wechatSection
                    moreSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(Palette.background)
        .codyncSheet(isPresented: $showingComputerUse) {
            NavigationStack { ComputerUseView() }
        }
        .codyncSheet(isPresented: $showingBotImport) {
            NavigationStack { BotImportView() }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        CardSection(title: L("状态")) {
            CardRow {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle().fill(Palette.tertiary).frame(width: 10, height: 10)
                        Text(L("桥接引擎未接通"))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.text)
                    }
                    Text(L("桥接引擎未接通：主机没有 IM 桥接，连接保存后待引擎接通才生效。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("每个连接指定一个智能体，收到的消息交给它回。桥只在 App 打开时收消息。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - One platform

    private func fieldLabels(for platform: String) -> (String, String, String) {
        switch platform {
        case "feishu":
            return (L("飞书"), L("App ID"), L("App Secret"))
        case "dingtalk":
            return (L("钉钉"), L("Client ID"), L("Client Secret"))
        default:
            return (L("Slack"), L("App 级令牌（xapp- 开头）"), L("智能体令牌（xoxb- 开头）"))
        }
    }

    private func platformCard(
        platform: String,
        field1: Binding<String>, field2: Binding<String>, botId: Binding<String>,
        error: Binding<String?>
    ) -> some View {
        let labels = fieldLabels(for: platform)
        let saved = connections.first { $0.platform == platform }
        return CardSection(title: labels.0) {
            if let saved {
                CardRow {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L("已保存"))
                                .font(.body)
                                .foregroundStyle(Palette.text)
                            Spacer()
                            Text(L("未接通"))
                                .font(.subheadline)
                                .foregroundStyle(Palette.tertiary)
                        }
                        Text(L("交给：%@；凭证只存在这部手机的钥匙串里。", botName(for: saved.botId)))
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(L("桥接引擎未接通：主机没有 IM 桥接，连接保存后待引擎接通才生效。"))
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Hairline()
                CardRow {
                    Button(L("删除连接"), role: .destructive) {
                        deleteConnection(saved)
                    }
                    .foregroundStyle(Palette.danger)
                }
            } else {
                CardRow {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField(labels.1, text: field1)
                            .font(.body)
                            .foregroundStyle(Palette.text)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        Hairline()
                        SecureField(labels.2, text: field2)
                            .font(.body)
                            .foregroundStyle(Palette.text)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        Hairline()
                        ValueRow(label: L("交给哪个智能体")) {
                            ChoicePicker(selection: botId, options: botOptions)
                        }
                        Text(L("凭证只存进这部手机的钥匙串，不写文件。"))
                            .font(.caption)
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let message = error.wrappedValue {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(Palette.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button(L("保存连接")) {
                            saveConnection(platform: platform, field1: field1.wrappedValue, field2: field2.wrappedValue, botId: botId.wrappedValue, error: error)
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.text)
                    }
                }
            }
        }
    }

    private var botOptions: [(id: String, label: String)] {
        [(id: "", label: L("不指定"))] + bots.map { (id: $0.id, label: $0.name) }
    }

    private func botName(for botId: String?) -> String {
        guard let botId, !botId.isEmpty else { return L("未指定") }
        return bots.first { $0.id == botId }?.name ?? L("未指定")
    }

    private func saveConnection(platform: String, field1: String, field2: String, botId: String, error: Binding<String?>) {
        let first = field1.trimmingCharacters(in: .whitespacesAndNewlines)
        let second = field2.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty, !second.isEmpty else {
            error.wrappedValue = L("两个凭证都要填。")
            return
        }
        if platform == "slack" {
            guard first.hasPrefix("xapp-"), second.hasPrefix("xoxb-") else {
                error.wrappedValue = L("Slack 令牌格式不对：App 级令牌以 xapp- 开头，智能体令牌以 xoxb- 开头。")
                return
            }
        }
        let connection = IMConnection(id: UUID(), platform: platform, botId: botId.isEmpty ? nil : botId, createdAt: Date())
        guard IMKeychain.save(first, account: connection.id.uuidString + ".field1"),
              IMKeychain.save(second, account: connection.id.uuidString + ".field2") else {
            IMKeychain.delete(account: connection.id.uuidString + ".field1")
            IMKeychain.delete(account: connection.id.uuidString + ".field2")
            error.wrappedValue = L("存进钥匙串失败，请重试。")
            return
        }
        connections.append(connection)
        IMConnectionStore.save(connections)
        error.wrappedValue = nil
        switch platform {
        case "feishu":
            feishuAppId = ""
            feishuSecret = ""
            feishuBotId = ""
        case "dingtalk":
            dingtalkClientId = ""
            dingtalkSecret = ""
            dingtalkBotId = ""
        default:
            slackAppToken = ""
            slackBotToken = ""
            slackBotId = ""
        }
    }

    private func deleteConnection(_ connection: IMConnection) {
        IMKeychain.delete(account: connection.id.uuidString + ".field1")
        IMKeychain.delete(account: connection.id.uuidString + ".field2")
        connections.removeAll { $0.id == connection.id }
        IMConnectionStore.save(connections)
    }

    // MARK: - Pairing and reassignment (no host method)

    private var pairingSection: some View {
        CardSection(title: L("配对与改派")) {
            CardRow {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L("首次配对批准"))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Text(L("不可用"))
                            .font(.subheadline)
                            .foregroundStyle(Palette.tertiary)
                    }
                    Text(L("有人第一次发消息时，须先配对批准才能回。主机没有这个方法，暂时不可用。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Hairline()
            CardRow {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L("按对话改派智能体或群"))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Text(L("不可用"))
                            .font(.subheadline)
                            .foregroundStyle(Palette.tertiary)
                    }
                    Text(L("每个对话可以单独改派给另一个智能体或群。主机没有这个方法，暂时不可用。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - WeChat (undecided)

    private var wechatSection: some View {
        CardSection(title: L("微信")) {
            CardRow {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L("微信扫码"))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Text(L("待定"))
                            .font(.subheadline)
                            .foregroundStyle(Palette.tertiary)
                    }
                    Text(L("微信扫码待定：扫码登录的方案还在定，本轮不做。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - More

    private var moreSection: some View {
        CardSection(title: L("更多")) {
            CardRow {
                Button {
                    showingComputerUse = true
                } label: {
                    HStack {
                        Text(L("电脑操作"))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            Hairline()
            CardRow {
                Button {
                    showingBotImport = true
                } label: {
                    HStack {
                        Text(L("导入智能体"))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One saved IM connection. Secrets are never stored here; only the two
/// keychain items keyed by `id.field1` / `id.field2` hold them.
struct IMConnection: Codable, Identifiable, Equatable {
    var id: UUID
    var platform: String
    var botId: String?
    var createdAt: Date
}

enum IMConnectionStore {
    private static let key = "cn.lingyu.imConnections.v1"

    static func load() -> [IMConnection] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let connections = try? JSONDecoder().decode([IMConnection].self, from: data) else {
            return []
        }
        return connections
    }

    static func save(_ connections: [IMConnection]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(connections), forKey: key)
    }
}

/// Keychain storage for IM credentials, mirroring VaultKeychain: one
/// generic-password item per value, this-device-only, never written to a
/// file and never printed.
enum IMKeychain {
    private static let service = "cn.lingyu.im-bridge"

    static func save(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
