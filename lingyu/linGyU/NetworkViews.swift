import SwiftUI

/// Network 页 (original NetworkSheet): a computer's networks of the
/// user's other computers, read-only — who is in each, whether each
/// one answers and which bots it offers, who may message this
/// computer's bots there, and whether cloud assistants may reach
/// them.
///
/// Only `networkView` is readable from a phone: the other `network*`
/// verbs (`networkCreate`, `networkJoin`, `networkInvite`,
/// `networkLeave`, `networkRecover`, `setNetworkRules`…) are
/// loopback-only — the host answers 403 "This can only be done at
/// the computer itself." So this page never offers create / join /
/// invite / rule edits; it says where those happen. The relay a
/// network runs on is chosen when the network is created on the
/// computer (`connector` on `networkCreate`: public relay, a
/// self-hosted relay, or private); the page shows each network's
/// relay as the host reports it, and offers no switch of its own —
/// the host has no phone-callable method to change it.
struct NetworkView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var status: NetworkStatus?
    @State private var loadError: String?
    @State private var loading = true

    /// Preview-only demo rows (seeded mode has no live host).
    private var isDemo: Bool { store.isPreview && store.connector.api == nil }

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("网络")) {
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if loading {
                        HStack(spacing: 8) {
                            Spinner(size: 14)
                            Text(L("正在读取网络…"))
                                .font(.subheadline)
                                .foregroundStyle(Palette.secondary)
                        }
                        .padding(.top, 8)
                    } else if let loadError {
                        DisabledNetworkCard(
                            title: L("无法读取网络"),
                            detail: loadError)
                    } else if let status {
                        networkBody(status)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .background(Palette.background)
        .task { await load() }
    }

    private func load() async {
        if isDemo {
            status = NetworkDemo.status
            loading = false
            return
        }
        guard let api = store.connector.api else {
            loadError = L("还没有连接电脑")
            loading = false
            return
        }
        do {
            status = try await api.networkView()
        } catch {
            loadError = networkErrorText(error)
        }
        loading = false
    }

    private func networkErrorText(_ error: Error) -> String {
        if let callError = error as? HostCallError {
            if callError.isUnknownMethod {
                return L("电脑端未提供网络视图")
            }
            if let message = callError.hostMessage, !message.isEmpty {
                return message
            }
        }
        return L("读取失败，请重试。")
    }

    @ViewBuilder
    private func networkBody(_ status: NetworkStatus) -> some View {
        if status.networks.isEmpty {
            DisabledNetworkCard(
                title: L("这台电脑还没有加入任何网络"),
                detail: L("新建或加入网络在电脑上操作。"))
        } else {
            ForEach(status.networks) { network in
                CardSection(title: network.name) {
                    ForEach(network.computers) { computer in
                        NetworkComputerRow(computer: computer)
                        if computer.id != network.computers.last?.id { Hairline() }
                    }
                    if let connector = network.connector, !connector.isEmpty {
                        Hairline()
                        CardRow {
                            ValueRow(label: L("中继"), detail: L("建网络时在电脑上选。")) {
                                Text(relayText(connector))
                                    .foregroundStyle(Palette.secondary)
                            }
                        }
                    }
                }
                if !network.rules.isEmpty {
                    CardSection(
                        title: L("谁可以给这里的智能体发消息"),
                        footer: L("更改在电脑上进行。")
                    ) {
                        ForEach(Array(network.rules.enumerated()), id: \.offset) { _, rule in
                            CardRow {
                                Text(rule.text)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            CardSection(footer: L("网络的更改在电脑上进行。")) {}
        }
        if status.assistantsAvailable {
            CardSection(footer: L("开启后，账户里的云端助手可以给这台电脑的智能体发消息。云端会读到这些通话。")) {
                CardRow {
                    ValueRow(label: L("云端助手")) {
                        Text(status.assistants ? L("开") : L("关"))
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }
        }
    }

    /// The relay as the host reports it: `public` is the shared
    /// relay, anything else is a self-hosted relay URL, `private`
    /// is a network with no relay at all.
    private func relayText(_ connector: String) -> String {
        switch connector {
        case "public": return L("公共中继")
        case "private": return L("不经过中继")
        default: return connector
        }
    }
}

private struct NetworkComputerRow: View {
    var computer: NetworkComputer

    var body: some View {
        CardRow {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(computer.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.text)
                    Spacer(minLength: 8)
                    if let role = computer.role, !role.isEmpty {
                        Text(roleTitle(role))
                            .font(.footnote)
                            .foregroundStyle(Palette.secondary)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle()
                        .fill(computer.online ? Palette.added : Palette.tertiary)
                        .frame(width: 7, height: 7)
                    Text(presence)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondary)
                }
                Text(bots)
                    .font(.footnote)
                    .foregroundStyle(Palette.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var presence: String {
        if computer.me { return L("这台电脑") }
        return computer.online ? L("在线") : L("离开")
    }

    private var bots: String {
        let names = computer.agents.map(\.name)
        return names.isEmpty ? L("没有智能体") : names.joined(separator: "、")
    }

    private func roleTitle(_ role: String) -> String {
        switch role {
        case "owner": return L("所有者")
        case "admin": return L("管理员")
        case "member": return L("成员")
        default: return role
        }
    }
}

/// A disabled block: a title, a reason, and nothing to tap.
private struct DisabledNetworkCard: View {
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.text)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Preview-only demo rows (seeded mode has no live host).
private enum NetworkDemo {
    static let status: NetworkStatus? = {
        let json = """
        {"joined":true,"networks":[{"id":"demo-net","key":"demo-key","name":"家里","computer":"ECS","role":"owner","canInvite":true,"canRecover":false,"connector":"public","computers":[{"name":"ECS","role":"owner","me":true,"online":true,"agents":[{"id":"demo-lead","name":"阿文","kind":"agent"}],"canRemove":false,"canPromote":false},{"name":"客厅电脑","role":"member","me":false,"online":false,"agents":[],"canRemove":true,"canPromote":true}],"rules":[{"fromComputer":"*","fromAgent":"*","toAgent":"*","access":"allow"}],"defaultAccess":"allow"}],"assistants":false,"assistantsAvailable":false}
        """
        return try? JSONDecoder().decode(NetworkStatus.self, from: Data(json.utf8))
    }()
}
