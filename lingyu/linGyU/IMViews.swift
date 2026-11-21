import SwiftUI
import Security

/// IM 桥接：把飞书、钉钉、Slack 的消息接给一个智能体回。
///
/// Login-style (2026-11-22): each platform is one row — name, status, a
/// Sign in button. Tapping it opens the provider's own login page in a
/// system authentication session (ASWebAuthenticationSession); this app
/// never shows an account, password, or token field. The client id and
/// secret live on the companion service on the paired computer (see
/// IMAuth.swift); the tokens it hands back go straight into the keychain.
///
/// Live probe on host 2.51.0 (2026-11-22): the host has no IM methods at
/// all (`imList` / `imConnections` both answer 404; the source has no
/// feishu / dingtalk / weixin / wecom code, and slack appears only as a
/// routine event source). So signing in only connects the account:
/// receiving messages still waits for the bridge engine, and the status
/// line says so. Pairing approval (`im-pair` / `im-unpair`) and
/// per-conversation reassignment have no host method either, so they stay
/// disabled with the reason. WeChat QR login is undecided for Phase 4 and
/// is not built.
struct IMBridgeView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var connections: [IMConnection] = IMConnectionStore.load()
    /// The bot picked for a platform that is not signed in yet; applied
    /// when the login completes.
    @State private var pendingBotId: [String: String] = [:]
    @State private var loginError: [String: String] = [:]
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
                    platformCard(platform: "feishu")
                    platformCard(platform: "dingtalk")
                    platformCard(platform: "slack")
                    setupSection
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
        .task {
            await store.imAuth.refreshStatus(computer: store.connector.computer)
        }
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
                    Text(L("登录只连通账号，收发消息仍等桥接引擎接通。"))
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

    private func platformName(_ platform: String) -> String {
        switch platform {
        case "feishu": return L("飞书")
        case "dingtalk": return L("钉钉")
        default: return L("Slack")
        }
    }

    private func platformCard(platform: String) -> some View {
        let saved = connections.first { $0.platform == platform }
        let loggingIn = store.imAuth.activePlatform == platform
        let status = store.imAuth.providerStatus[platform]
        return CardSection(title: platformName(platform)) {
            CardRow {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(platformName(platform))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        if let saved {
                            Text(saved.isExpired ? L("已过期") : L("已连接"))
                                .font(.subheadline)
                                .foregroundStyle(saved.isExpired ? Palette.danger : Palette.secondary)
                        } else {
                            Text(L("未连接"))
                                .font(.subheadline)
                                .foregroundStyle(Palette.tertiary)
                        }
                    }
                    if let saved {
                        HStack(spacing: 10) {
                            IMAvatarView(name: saved.displayName, url: saved.avatarURL)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(saved.displayName ?? platformName(platform))
                                    .font(.body)
                                    .foregroundStyle(Palette.text)
                                if let team = saved.teamName, !team.isEmpty {
                                    Text(team)
                                        .font(.subheadline)
                                        .foregroundStyle(Palette.secondary)
                                }
                            }
                            Spacer()
                            Button(L("断开"), role: .destructive) {
                                disconnect(saved)
                            }
                            .foregroundStyle(Palette.danger)
                        }
                        if saved.isExpired {
                            Text(L("令牌已过期，请重新登录。"))
                                .font(.subheadline)
                                .foregroundStyle(Palette.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if platform == "dingtalk" {
                            Text(L("钉钉令牌 2 小时有效，到期后请重新登录。"))
                                .font(.subheadline)
                                .foregroundStyle(Palette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(L("令牌只存在这部手机的钥匙串里，不写文件、不显示。"))
                            .font(.caption)
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ValueRow(label: L("交给哪个智能体")) {
                        ChoicePicker(selection: botBinding(platform: platform, saved: saved), options: botOptions)
                    }
                    if saved == nil || saved?.isExpired == true {
                        Button {
                            login(platform: platform)
                        } label: {
                            if loggingIn {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text(L("登录"))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.primary)
                        .disabled(loggingIn)
                        Text(L("点登录后去对方页面授权，App 里不填账号密码。"))
                            .font(.caption)
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let message = loginError[platform] {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if status?.loginReady == false, status?.detail == "https-required" {
                        Text(L("Slack 登录需要 HTTPS 回调地址，陪跑服务还没有 HTTPS，暂时登不上。"))
                            .font(.footnote)
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var botOptions: [(id: String, label: String)] {
        [(id: "", label: L("不指定"))] + bots.map { (id: $0.id, label: $0.name) }
    }

    /// The bot picker binding: for a signed-in platform it edits the saved
    /// record; before sign-in it keeps the choice to apply on login.
    private func botBinding(platform: String, saved: IMConnection?) -> Binding<String> {
        if let saved, let index = connections.firstIndex(of: saved) {
            return Binding(
                get: { connections[index].botId ?? "" },
                set: { newValue in
                    connections[index].botId = newValue.isEmpty ? nil : newValue
                    IMConnectionStore.save(connections)
                }
            )
        }
        return Binding(
            get: { pendingBotId[platform] ?? "" },
            set: { pendingBotId[platform] = $0 }
        )
    }

    private func login(platform: String) {
        guard let computer = store.connector.computer else {
            loginError[platform] = L("需要先配对电脑：陪跑服务跑在你配对的电脑上。")
            return
        }
        loginError[platform] = nil
        let botId = pendingBotId[platform] ?? ""
        Task {
            do {
                let result = try await store.imAuth.startLogin(platform: platform, computer: computer)
                saveLogin(platform: platform, botId: botId, result: result)
            } catch where IMAuthError.isCancellation(error) {
                // The user closed the sign-in sheet: silent.
            } catch {
                loginError[platform] = (error as? LocalizedError)?.errorDescription ?? L("登录失败，请重试。")
            }
        }
    }

    private func saveLogin(platform: String, botId: String, result: IMLoginResult) {
        let connection = IMConnection(
            id: UUID(), platform: platform,
            botId: botId.isEmpty ? nil : botId,
            createdAt: Date(),
            displayName: result.displayName,
            avatarURL: result.avatarURL,
            teamName: result.teamName,
            expiresAt: result.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        )
        guard IMKeychain.save(result.accessToken, account: connection.id.uuidString + ".accessToken") else {
            loginError[platform] = L("存进钥匙串失败，请重试。")
            return
        }
        if let refreshToken = result.refreshToken {
            guard IMKeychain.save(refreshToken, account: connection.id.uuidString + ".refreshToken") else {
                IMKeychain.delete(account: connection.id.uuidString + ".accessToken")
                loginError[platform] = L("存进钥匙串失败，请重试。")
                return
            }
        }
        connections.removeAll { $0.platform == platform }
        connections.append(connection)
        IMConnectionStore.save(connections)
        pendingBotId[platform] = nil
        loginError[platform] = nil
    }

    private func disconnect(_ connection: IMConnection) {
        IMKeychain.delete(account: connection.id.uuidString + ".accessToken")
        IMKeychain.delete(account: connection.id.uuidString + ".refreshToken")
        connections.removeAll { $0.id == connection.id }
        IMConnectionStore.save(connections)
    }

    // MARK: - One-time setup (browser, not in-app)

    private var setupSection: some View {
        CardSection(title: L("登录前要做的事")) {
            CardRow {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("在浏览器里给每个平台建一个应用，拿到它的 ID 与密钥。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("把 ID 与密钥交给陪跑服务（跑在你配对的电脑上，一次就好）。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("回调地址填陪跑服务的地址；Slack 只能用 HTTPS，见说明。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
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

/// The signed-in account's avatar: the provider's image when it loads,
/// otherwise a disc with the first character of the name.
private struct IMAvatarView: View {
    var name: String?
    var url: String?

    var body: some View {
        if let url, let imageURL = URL(string: url) {
            AsyncImage(url: imageURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    initialDisc
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(Circle())
        } else {
            initialDisc
                .frame(width: 28, height: 28)
        }
    }

    private var initialDisc: some View {
        ZStack {
            Circle().fill(Palette.surface)
            Text(String((name ?? "?").prefix(1)))
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.text)
        }
    }
}

/// One signed-in IM account. Tokens are never stored here; only the two
/// keychain items keyed by `id.accessToken` / `id.refreshToken` hold them.
struct IMConnection: Codable, Identifiable, Equatable {
    var id: UUID
    var platform: String
    var botId: String?
    var createdAt: Date
    var displayName: String?
    var avatarURL: String?
    var teamName: String?
    var expiresAt: Date?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }
}

enum IMConnectionStore {
    private static let key = "cn.lingyu.imConnections.v1"

    /// Loads the signed-in accounts. Records from the old credential form
    /// (no display name — they were never usable, the bridge engine never
    /// existed) are dropped here, together with their keychain items; the
    /// new login flow replaces them.
    static func load() -> [IMConnection] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let connections = try? JSONDecoder().decode([IMConnection].self, from: data) else {
            return []
        }
        let kept = connections.filter { $0.displayName != nil }
        if kept.count != connections.count {
            for dropped in connections where dropped.displayName == nil {
                IMKeychain.delete(account: dropped.id.uuidString + ".field1")
                IMKeychain.delete(account: dropped.id.uuidString + ".field2")
            }
            save(kept)
        }
        return kept
    }

    static func save(_ connections: [IMConnection]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(connections), forKey: key)
    }
}

/// Keychain storage for IM tokens, mirroring VaultKeychain: one
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
