import SwiftUI

/// Relative time formats (§3.4). Rules (thresholds and segments) are the
/// originals'; the words are localised for the Chinese UI.
enum RelativeTime {
    /// Roster row time: today → short time; yesterday → "昨天";
    /// within 6 days → weekday name; earlier → "9月16日".
    static func day(_ millis: Int64) -> String {
        guard millis > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if calendar.isDateInToday(date) {
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return formatter.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return L("昨天")
        }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day,
           days < 7 {
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        }
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    /// Short relative time: now / 5分钟 / 3小时 / 2天 / 9月3日.
    static func short(_ millis: Int64) -> String {
        guard millis > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return L("刚刚") }
        if seconds < 3600 { return L("%d分钟前", Int(seconds / 60)) }
        if seconds < 86400 { return L("%d小时前", Int(seconds / 3600)) }
        if seconds < 7 * 86400 { return L("%d天前", Int(seconds / 86400)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    /// Chat message time: 24-hour clock precise to the second ("12:53:02").
    /// Uses the message's own event time (Entry.createdAt), never render time.
    static func clock(_ millis: Int64) -> String {
        guard millis > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    /// Chat time separator: today → "今天 3:27"; yesterday → "昨天 5:20";
    /// earlier → "9月16日 9:02".
    static func separator(_ millis: Int64) -> String {
        guard millis > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_CN")
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        let time = timeFormatter.string(from: date)
        if calendar.isDateInToday(date) {
            return L("今天 %@", time)
        }
        if calendar.isDateInYesterday(date) {
            return L("昨天 %@", time)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return "\(formatter.string(from: date)) \(time)"
    }
}

struct BotListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingNewBot = false
    @State private var showingWork = false
    @State private var showingAccount = false
    @State private var showingComputers = false
    @State private var showingNewGroup = false
    @State private var showingIncognito = false

    private var mirror: EventMirror { store.connector.mirror }

    /// The toolbar badge counts working tasks, not bots.
    private var workingTaskCount: Int {
        mirror.bots.flatMap(\.work).filter { $0.status == "working" }.count
    }

    private var hasWork: Bool {
        mirror.bots.contains { !$0.workSections.isIdle }
    }

    var body: some View {
        List {
            if mirror.bots.isEmpty {
                emptyState
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(mirror.bots) { bot in
                    BotRow(bot: bot)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .background(Palette.background)
        .navigationTitle(L("智能体"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                AccountSwitcherButton {
                    showingAccount = true
                }
            }
            ToolbarItem(placement: .principal) {
                ComputerFilterHeader {
                    showingComputers = true
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if hasWork {
                    Button {
                        showingWork = true
                    } label: {
                        Label(L("工作"), systemImage: "tray.full")
                    }
                    .badge(workingTaskCount)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu(L("新建"), systemImage: "plus") {
                    Button {
                        showingNewBot = true
                    } label: {
                        Label(L("新建智能体"), systemImage: "plus")
                    }
                    Button {
                        showingNewGroup = true
                    } label: {
                        Label(L("新建群聊"), systemImage: "person.2")
                    }
                    .disabled(!isOnline)
                    Button {
                        showingIncognito = true
                    } label: {
                        Label(L("新建私密会话"), systemImage: "lock")
                    }
                }
                .disabled(!store.connector.isPaired)
            }
        }
        .refreshable {
            await store.connector.disconnect()
            await store.connector.connectIfPaired()
        }
        .codyncSheet(isPresented: $showingAccount) {
            AccountSwitcherView()
        }
        .codyncSheet(isPresented: $showingComputers) {
            ComputersView()
        }
        .codyncSheet(isPresented: $showingWork) {
            AllWorkView()
        }
        .codyncSheet(isPresented: $showingNewBot) {
            NewBotView()
        }
        .codyncSheet(isPresented: $showingNewGroup) {
            NewGroupView()
        }
        .codyncSheet(isPresented: $showingIncognito) {
            IncognitoBotPicker()
        }
    }

    private var isOnline: Bool {
        if case .ready = store.connector.state { return true }
        return false
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            CharacterAvatar(shape: "cloud", color: "green", size: 72)
            Text(L("还没有智能体"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.text)
            Text(L("新建一个智能体，给它起个名字、指一个项目。"))
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
            if store.connector.isPaired {
                Button(L("新建智能体")) {
                    showingNewBot = true
                }
                .buttonStyle(.primary)
            } else {
                Button(L("配对电脑")) {
                    store.showingPairing = true
                }
                .buttonStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// The account button in the toolbar: the user's avatar and a chevron,
/// opening the account switcher.
struct AccountSwitcherButton: View {
    var action: () -> Void

    var body: some View {
        let name = UserDefaults.standard.string(forKey: "cn.lingyu.myName")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        Button(action: action) {
            HStack(spacing: 6) {
                AvatarView(name: name.isEmpty ? L("我") : name, color: "blue", shape: "blob", size: 30, ownerId: AvatarStore.meOwnerId)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("切换账号"))
    }
}

/// The account switcher: the one local account, with a way to edit the
/// profile in Settings. (There is no cloud account to switch to.)
struct AccountSwitcherView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("账号")) {
                dismiss()
            }
            ScrollView {
                VStack(spacing: 24) {
                    CardSection {
                        CardRow {
                            HStack(spacing: 14) {
                                let name = UserDefaults.standard.string(forKey: "cn.lingyu.myName")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                AvatarView(name: name.isEmpty ? L("我") : name, color: "blue", shape: "blob", size: 48, ownerId: AvatarStore.meOwnerId)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(name.isEmpty ? L("我") : name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Palette.text)
                                    Text(L("本机账号"))
                                        .font(.subheadline)
                                        .foregroundStyle(Palette.secondary)
                                }
                                Spacer(minLength: 12)
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Palette.text)
                            }
                        }
                        Hairline()
                        CardRow {
                            Button(L("我的资料")) {
                                dismiss()
                                store.selectedTab = 3
                            }
                            .foregroundStyle(Palette.text)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .background(Palette.background)
    }
}

/// The computer filter in the toolbar's center: how many computers are
/// connected, and a menu to pick them, reconnect, or manage them.
struct ComputerFilterHeader: View {
    @EnvironmentObject private var store: AppStore
    var onManage: () -> Void

    private var connectedCount: Int {
        if case .ready = store.connector.state { return 1 }
        return 0
    }

    var body: some View {
        Menu {
            Toggle(isOn: .constant(true)) {
                Label(L("所有电脑"), systemImage: "desktopcomputer")
            }
            ForEach(store.connector.computers) { computer in
                Button {
                    Task { await store.connector.selectComputer(computer) }
                } label: {
                    Label {
                        Text(computer.name)
                    } icon: {
                        if store.connector.computer?.id == computer.id {
                            Image(systemName: "checkmark")
                        } else {
                            ComputerBadge(computer: computer)
                        }
                    }
                }
            }
            Divider()
            Button {
                Task {
                    await store.connector.disconnect()
                    await store.connector.connectIfPaired()
                }
            } label: {
                Label(L("重新连接"), systemImage: "arrow.clockwise")
            }
            Button(action: onManage) {
                Label(L("管理电脑"), systemImage: "gearshape")
            }
        } label: {
            HStack(spacing: 6) {
                Text(L("%d 台已连接", connectedCount))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.text)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

/// A computer's badge: 28pt, its icon in a light rounded square.
/// The icon follows the original ComputerBadge symbol map by device;
/// linux uses the `computer-linux` asset — linGyU has no such asset yet,
/// so linux falls back to `desktopcomputer` until one is added.
struct ComputerBadge: View {
    var computer: Computer?

    /// The original's per-device symbol (ComputerBadge.symbol).
    static func symbol(_ device: String?) -> String {
        switch device {
        case "laptop": return "laptopcomputer"
        case "macmini": return "macmini"
        case "macstudio": return "macstudio"
        case "imac": return "desktopcomputer"
        case "macpro": return "macpro.gen3"
        case "cloud": return "cloud"
        default: return "desktopcomputer"
        }
    }

    /// The badge icon at a given glyph size, for rows that don't use the
    /// 28pt badge chrome (same symbol map; linux asset when it exists).
    @ViewBuilder
    static func icon(for computer: Computer?, size: CGFloat) -> some View {
        if computer?.device == "linux", UIImage(named: "computer-linux") != nil {
            Image("computer-linux").resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Image(systemName: symbol(computer?.device))
                .font(.system(size: size, weight: .medium))
        }
    }

    var body: some View {
        Self.icon(for: computer, size: 14)
            .foregroundStyle(Palette.secondary)
            .frame(width: 28, height: 28)
            .background(Palette.bubbleUser, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// One roster row (§3.2): 46pt avatar, name + time, preview + badge.
/// A plain Button — the same push as a link, without a chevron.
struct BotRow: View {
    var bot: Bot
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Button {
            store.navigationPath.append(bot.id)
        } label: {
            HStack(spacing: 12) {
                AvatarWithStatus(bot: bot, members: members, size: 46)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if bot.pinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(Palette.tertiary)
                        }
                        Text(bot.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(RelativeTime.day(bot.lastAt))
                            .font(.subheadline)
                            .foregroundStyle(bot.unread > 0 ? Palette.text : Palette.tertiary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        preview
                        Spacer(minLength: 4)
                        if bot.unread > 0 {
                            UnreadBadge(count: bot.unread, waiting: bot.waiting > 0)
                        }
                    }
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var members: [Bot] {
        bot.members.compactMap { store.connector.mirror.bot(id: $0) }
    }

    @ViewBuilder
    private var preview: some View {
        // Preview priority (§3.3): needsYou > activity > work > lastMessage.
        switch bot.rosterLine {
        case .needsYou:
            ThinkingOrb(state: .listening, size: 16, color: Palette.warning)
            Text(bot.needsYouLine)
                .font(.subheadline)
                .foregroundStyle(Palette.warning)
                .lineLimit(1)
        case .activity:
            ThinkingOrb(state: .working, size: 13, color: Palette.secondary)
            Text(bot.activity.isEmpty ? L("工作中…") : bot.activity)
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
        case .work:
            ThinkingOrb(state: .working, size: 13, color: Palette.secondary)
            Text(bot.workSections.counts())
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
        case .lastMessage:
            if let lastMessage = bot.lastMessage, !lastMessage.isEmpty {
                Text(lastMessage)
                    .font(.subheadline)
                    .foregroundStyle(bot.status == "error" ? Palette.danger : Palette.secondary)
                    .lineLimit(1)
            } else if bot.isGroup {
                Text(L("%d 个智能体", bot.members.count))
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            } else {
                Text("\(bot.backend) · \(bot.folderDisplay)")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct UnreadBadge: View {
    var count: Int
    var waiting: Bool

    var body: some View {
        Text("\(count)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(waiting ? Palette.onWarning : Palette.onAccent)
            .padding(.horizontal, 6)
            .frame(minWidth: 18, minHeight: 18)
            .background(waiting ? Palette.warning : Palette.accentFill, in: Capsule())
    }
}

/// The computer-management sheet, matching the original's ComputersView:
/// one card per paired computer (summary + extensions / voice / network
/// while the current computer is online + notifications + auto-order +
/// connection + add-to-account + host version), the account's unpaired
/// computers, the pair button, and the cloud section — all from real
/// data only.
struct ComputersView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var forgettingComputer: Computer?
    @State private var showingNewCloudDialog = false
    @State private var updatingComputerId: String?
    @State private var updatingFromVersion: String?
    @State private var showingExtensions = false
    @State private var showingVoice = false
    @State private var showingNetwork = false
    /// Whether the host answers `networkView`: nil until probed,
    /// false when the host has no such method.
    @State private var networkAvailable: Bool?
    @State private var joiningAccount = false
    @State private var joinError: String?
    @State private var joinDone = false

    /// LinkState carries associated values and is not Equatable, so the
    /// codebase tests readiness with `if case` (see BotListView.isOnline).
    private var isOnline: Bool {
        if case .ready = store.connector.state { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("电脑管理")) {
                dismiss()
            }
            ScrollView {
                VStack(spacing: 24) {
                    ForEach(store.connector.computers) { computer in
                        CardSection {
                            computerCard(computer)
                        }
                    }
                    ForEach(accountOnlyComputers) { account in
                        CardSection {
                            accountComputerRow(account)
                        }
                    }
                    CardSection(footer: pairFooter) {
                        Button {
                            dismiss()
                            store.showingPairing = true
                        } label: {
                            Label(L("配对一台电脑"), systemImage: "qrcode.viewfinder")
                                .foregroundStyle(Palette.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if store.cloudAvailable || !store.cloudMachines.isEmpty {
                        cloudSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .background(Palette.background)
        .codyncDialog(
            isPresented: Binding(
                get: { forgettingComputer != nil },
                set: { if !$0 { forgettingComputer = nil } }
            ),
            title: L("忘记这台电脑？"),
            message: L("这部手机将断开与这台电脑的连接。电脑上仍会列出这部设备，需要时请在电脑上撤销。"),
            actions: [
                CodyncDialogAction(title: L("取消")) {},
                CodyncDialogAction(title: L("忘记"), isDestructive: true) {
                    if let computer = forgettingComputer {
                        store.connector.forgetComputer(computer)
                    }
                    forgettingComputer = nil
                },
            ]
        )
        .codyncDialog(
            isPresented: $showingNewCloudDialog,
            title: L("新建云电脑"),
            message: L("新建云电脑稍后推出。现在可以先用已有的云电脑。"),
            actions: [
                CodyncDialogAction(title: L("好")) {},
            ]
        )
        .onAppear {
            if store.account.isSignedIn {
                Task { await store.refreshAccountCloud() }
            }
        }
        .onChange(of: store.account.isSignedIn) { _, signedIn in
            if signedIn {
                Task { await store.refreshAccountCloud() }
            } else {
                store.clearAccountCloud()
            }
        }
        .onChange(of: store.connector.hello?.version) { _, version in
            if let version, updatingComputerId != nil, version != updatingFromVersion {
                updatingComputerId = nil
            }
        }
        .task(id: updatingComputerId) {
            guard updatingComputerId != nil else { return }
            try? await Task.sleep(for: .seconds(600))
            updatingComputerId = nil
        }
        .codyncSheet(isPresented: $showingExtensions) {
            ExtensionsView()
        }
        .codyncSheet(isPresented: $showingVoice) {
            // B 号代理的语音设置页 (VoiceSettingsViews.swift):
            // struct VoiceSettingsView, 已核对名字一致。
            VoiceSettingsView()
        }
        .codyncSheet(isPresented: $showingNetwork) {
            NetworkView()
        }
        .task(id: isOnline) {
            await probeNetwork()
        }
    }

    /// The account's computers that are not paired on this phone, for the
    /// information-only cards between the paired computers and the pair
    /// button (original AccountComputerRows).
    private var accountOnlyComputers: [AccountComputer] {
        store.accountComputers.filter { account in
            !store.connector.computers.contains { $0.id == account.computerId }
        }
    }

    /// One paired computer: summary, extensions / voice / network
    /// (current computer only, while it is online), notifications,
    /// auto-order (current computer only, when the host reports it),
    /// connection, add-to-account (current computer only, while it
    /// is not in the account yet), host version.
    private func computerCard(_ computer: Computer) -> some View {
        let isCurrent = store.connector.computer?.id == computer.id
        let hello = isCurrent ? store.connector.hello : nil
        return Group {
            summaryRow(computer)
            if isCurrent, isOnline {
                Hairline()
                extensionsRow
                Hairline()
                voiceRow
                Hairline()
                networkRow
            }
            Hairline()
            notificationsRow(computer)
            if hello.flatMap({ $0.autoOrder }) != nil {
                Hairline()
                autoOrderRow
            }
            Hairline()
            connectionRow
            if isCurrent, !isInAccount(computer.id) {
                Hairline()
                addToAccountRow
            }
            if let hello {
                Hairline()
                versionRow(computer, hello: hello)
            }
        }
    }

    /// Extensions, voice chat and network (original ComputerRows):
    /// only for the current computer while it is online — the
    /// destinations read from its live host.
    private var extensionsRow: some View {
        CardRow {
            Button { showingExtensions = true } label: {
                ComputerRowLabel(text: L("扩展"), systemImage: "square.grid.2x2", chevron: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var voiceRow: some View {
        CardRow {
            Button { showingVoice = true } label: {
                ComputerRowLabel(text: L("语音"), systemImage: "waveform", chevron: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var networkRow: some View {
        CardRow {
            if networkAvailable == false {
                ComputerRowLabel(text: L("网络"), systemImage: "network", value: L("电脑端未提供"))
                    .opacity(0.5)
            } else {
                Button { showingNetwork = true } label: {
                    ComputerRowLabel(text: L("网络"), systemImage: "network", chevron: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Asks the host once whether it answers `networkView`, so the
    /// network row can sit disabled with a reason when it doesn't.
    /// Any other failure leaves the row enabled; the page reports it.
    private func probeNetwork() async {
        guard isOnline, let api = store.connector.api else { return }
        guard networkAvailable == nil else { return }
        do {
            _ = try await api.networkView()
            networkAvailable = true
        } catch {
            if let callError = error as? HostCallError, callError.isUnknownMethod {
                networkAvailable = false
            }
        }
    }

    /// Bring this computer into the account (original
    /// AddToAccountRow): only for the current computer while it is
    /// not in the account yet. Signed out: a disabled row with the
    /// reason and a sign-in entry. Signed in: starts the claim flow
    /// (`createClaim` → host `joinAccount` → `completeClaim`); the
    /// host still refuses until the device-certificate flow lands,
    /// and the row says so instead of pretending it worked.
    private var addToAccountRow: some View {
        CardRow {
            VStack(alignment: .leading, spacing: 8) {
                if store.account.isSignedIn {
                    HStack(spacing: 12) {
                        Button {
                            Task { await requestJoinAccount() }
                        } label: {
                            ComputerRowLabel(text: L("加入账户"), systemImage: "person.crop.circle.badge.plus", chevron: !joiningAccount)
                        }
                        .buttonStyle(.plain)
                        .disabled(joiningAccount || joinDone)
                        if joiningAccount {
                            Spinner(size: 16)
                        }
                    }
                    if joinDone {
                        Text(L("已加入账户"))
                            .font(.footnote)
                            .foregroundStyle(Palette.secondary)
                    } else if let joinError {
                        Text(joinError)
                            .font(.footnote)
                            .foregroundStyle(Palette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if store.connector.hello?.canJoinAccount == false {
                        Text(L("这台电脑现在不能加入账户"))
                            .font(.footnote)
                            .foregroundStyle(Palette.secondary)
                    }
                } else {
                    ComputerRowLabel(text: L("加入账户"), systemImage: "person.crop.circle.badge.plus", value: L("需先登录账号"))
                        .opacity(0.5)
                    Button(L("登录账号")) {
                        dismiss()
                        store.selectedTab = 3
                        Task {
                            try? await Task.sleep(for: .milliseconds(400))
                            await MainActor.run { store.showingSignIn = true }
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.text)
                }
            }
        }
    }

    private func requestJoinAccount() async {
        guard let api = store.connector.api, let cloud = store.account.cloudClient() else { return }
        joiningAccount = true
        joinError = nil
        joinDone = false
        do {
            let claim = try await cloud.createClaim()
            let signed = try await api.joinAccount(claimId: claim.claimId, nonce: claim.nonce, certificate: nil)
            try await cloud.completeClaim(claimId: claim.claimId, claim: signed)
            joinDone = true
            await store.refreshAccountCloud()
        } catch {
            joinError = joinErrorText(error)
        }
        joiningAccount = false
    }

    private func joinErrorText(_ error: Error) -> String {
        if let callError = error as? HostCallError, let message = callError.hostMessage, !message.isEmpty {
            if message.localizedCaseInsensitiveContains("confirm") {
                return L("加入账户需要设备证书，尚未接通。")
            }
            return message
        }
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return localized
        }
        return L("加入账户失败，请重试。")
    }

    /// Name, account checkmark, cloud hosting line, and the live
    /// connection detail (original ComputerRows.summary).
    private func summaryRow(_ computer: Computer) -> some View {
        CardRow {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    ComputerBadge(computer: computer)
                    Text(computer.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isInAccount(computer.id) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .foregroundStyle(Palette.tertiary)
                    }
                }
                if let hosting = accountHosting(for: computer.id) {
                    Text(L("运行于 %@ · %@", hosting.providerName, hosting.region))
                        .font(.footnote)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                Text(detailText(for: computer))
                    .font(.footnote)
                    .foregroundStyle(detailColor(for: computer))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
            .contextActions {
                var items: [MenuItem] = []
                if store.connector.computer?.id == computer.id, isOnline {
                    items.append(MenuItem(L("扩展"), icon: "square.grid.2x2") { showingExtensions = true })
                    items.append(MenuItem(L("语音"), icon: "waveform") { showingVoice = true })
                    if networkAvailable != false {
                        items.append(MenuItem(L("网络"), icon: "network") { showingNetwork = true })
                    }
                }
                items.append(MenuItem(L("忘记这台电脑"), icon: "trash", destructive: true) {
                    forgettingComputer = computer
                })
                return items
            }
        }
    }

    private func isInAccount(_ computerId: String) -> Bool {
        store.accountComputers.contains { $0.computerId == computerId }
    }

    private func accountHosting(for computerId: String) -> CloudHosting? {
        store.accountComputers.first { $0.computerId == computerId }?.cloud
    }

    /// The live connection detail under the name (original
    /// ComputerStatus.statusText): bots + direct route when online, the
    /// connection state otherwise. A computer that is not current is
    /// honestly "未连接" — this app keeps one connection.
    private func detailText(for computer: Computer) -> String {
        let isCurrent = store.connector.computer?.id == computer.id
        guard isCurrent else { return L("未连接") }
        switch store.connector.state {
        case .ready:
            return L("%d 个智能体 · 直连", store.connector.mirror.bots.count)
        case .connecting:
            return L("连接中…")
        case .waiting:
            return L("重连中…")
        case .stopped:
            return L("离线")
        case .offline:
            return L("未连接")
        }
    }

    private func detailColor(for computer: Computer) -> Color {
        let isCurrent = store.connector.computer?.id == computer.id
        guard isCurrent else { return Palette.secondary }
        switch store.connector.state {
        case .ready, .connecting, .waiting:
            return Palette.secondary
        case .stopped, .offline:
            return Palette.warning
        }
    }

    /// Push notifications, stored per computer, default on (original
    /// ComputerNotifications).
    private func notificationsRow(_ computer: Computer) -> some View {
        CardRow {
            Toggle(isOn: Binding(
                get: { computer.notifications ?? true },
                set: { store.connector.setNotifications($0, for: computer.id) }
            )) {
                ComputerRowLabel(text: L("推送通知"), systemImage: "bell")
            }
            .toggleStyle(.codync)
        }
    }

    /// Bots with new messages move to the top (original AutoOrderRow): a
    /// host setting, written with one inner RPC and optimistically
    /// updated. Only when the host reported a value.
    private var autoOrderRow: some View {
        CardRow {
            Toggle(isOn: Binding(
                get: { store.connector.hello?.autoOrder ?? false },
                set: { enabled in Task { await store.connector.setAutoOrder(enabled) } }
            )) {
                ComputerRowLabel(text: L("将有新动态的机器人移到最前面"), systemImage: "arrow.up")
            }
            .toggleStyle(.codync)
        }
    }

    /// The connection (original ConnectionRow): this build has no relay
    /// transport, so the only mode is direct — shown as a static row, no
    /// menu, exactly like the original renders a computer without cloud.
    private var connectionRow: some View {
        CardRow {
            ComputerRowLabel(text: L("连接"), systemImage: "arrow.triangle.branch", value: L("自动"))
        }
    }

    /// The host version (original CodyncVersionRow), labelled neutrally:
    /// the real version from the hello handshake, plus update state.
    private func versionRow(_ computer: Computer, hello: HelloReply) -> some View {
        let info = versionInfo(hello)
        return CardRow {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 17))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(L("服务端"))
                        Text(verbatim: hello.version)
                            .foregroundStyle(Palette.secondary)
                            .monospacedDigit()
                    }
                    if !info.detail.isEmpty {
                        Text(info.detail)
                            .font(.footnote)
                            .foregroundStyle(info.warns ? Palette.warning : Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if updatingComputerId == computer.id {
                    Spinner(size: 16)
                } else if info.updateAvailable {
                    Button(L("更新")) { requestUpdate(for: computer) }
                        .buttonStyle(.primary)
                }
            }
            .foregroundStyle(Palette.text)
        }
    }

    private func versionInfo(_ hello: HelloReply) -> (detail: String, warns: Bool, updateAvailable: Bool) {
        if let unsupported = Compatibility.unsupportedMessage(for: hello) {
            return (unsupported, true, false)
        }
        guard let latest = hello.latestVersion, !latest.isEmpty else {
            return ("", false, false)
        }
        guard Compatibility.compare(hello.version, latest) == .orderedAscending else {
            return (L("已是最新版本"), false, false)
        }
        if hello.canUpdate {
            return (L("%@ 版可用。", latest), false, true)
        }
        return (L("%@ 版可用。", latest), false, false)
    }

    /// Asks the host to update itself; the spinner clears when the hello
    /// comes back with a new version, or after 10 minutes.
    private func requestUpdate(for computer: Computer) {
        updatingComputerId = computer.id
        updatingFromVersion = store.connector.hello?.version
        Task {
            do {
                guard let api = store.connector.api else {
                    updatingComputerId = nil
                    return
                }
                try await api.installHostUpdate()
            } catch {
                updatingComputerId = nil
            }
        }
    }

    /// An account computer not paired on this phone (original
    /// AccountComputerRow): dimmed badge, name, status line, hosting
    /// line. Information only — the access-request API is not in this
    /// build, so there is no action button (open gap).
    private func accountComputerRow(_ account: AccountComputer) -> some View {
        CardRow {
            HStack(spacing: 12) {
                Image(systemName: ComputerBadge.symbol(account.cloud != nil ? "cloud" : nil))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 28, height: 28)
                    .background(Palette.bubbleUser, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .opacity(0.5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.text)
                    Text(accountDetail(account))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(2)
                    if let cloud = account.cloud {
                        Text(L("运行于 %@ · %@", cloud.providerName, cloud.region))
                            .font(.footnote)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func accountDetail(_ account: AccountComputer) -> String {
        if let cloud = account.cloud, cloud.isAsleep {
            return L("休眠 · 发消息时唤醒")
        }
        let online = account.isOnline ? L("在线") : L("离线")
        return L("%@ · 在你的账户里", online)
    }

    /// The pair section's footer (original ComputersView): the wording
    /// depends on sign-in state.
    private var pairFooter: String {
        store.account.isSignedIn
            ? L("账户里的电脑要先在电脑上同意，这台 iPhone 才能使用。")
            : L("每个智能体都在自己的电脑上运行。登录后可以看到账户里的电脑。")
    }

    /// The cloud section (original CloudComputerSection): only real
    /// machines from the account cloud, shown when the account can have
    /// one or has any. Never a preset, never a dependency of the local
    /// computers above.
    private var cloudSection: some View {
        CardSection(
            title: L("云电脑"),
            footer: L("运行在你自己的云端供应商账户上，供应商按它醒着的时间向你收费。闲置时休眠，你发消息时唤醒。"),
            accessory: AnyView(cloudAccessory)
        ) {
            ForEach(store.cloudMachines) { machine in
                cloudMachineRow(machine)
                if machine.id != store.cloudMachines.last?.id {
                    Hairline()
                }
            }
        }
    }

    private var cloudAccessory: some View {
        HStack(spacing: 4) {
            Text(L("测试版"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Palette.bubbleAgent, in: Capsule())
            if store.cloudAvailable {
                Button {
                    showingNewCloudDialog = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func cloudMachineRow(_ machine: CloudMachine) -> some View {
        CardRow {
            HStack(spacing: 12) {
                ProviderMascot(providerId: machine.provider, providerName: machine.providerName, size: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: machine.name)
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Text("\(machine.providerName) · \(machine.region) · \(machineStateText(machine))")
                        .font(.caption)
                        .foregroundStyle(machine.state == "failed" ? Palette.danger : Palette.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The machine's live state (original CloudComputerSection.status):
    /// a preparing machine reports that first, otherwise its state word.
    private func machineStateText(_ machine: CloudMachine) -> String {
        if machine.computerId == nil, machine.state != "failed" {
            return L("正在准备云电脑…")
        }
        switch machine.state {
        case "starting": return L("启动中")
        case "running": return L("运行中")
        case "stopping": return L("休眠中")
        case "stopped": return L("休眠")
        case "failed": return L("异常")
        default: return L("未知")
        }
    }
}

/// A computer-management row label (original RowLabel): 17pt icon in a
/// 26pt slot, text, optional trailing value, optional chevron.
private struct ComputerRowLabel: View {
    var text: String
    var systemImage: String
    var value: String? = nil
    var chevron: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17))
                .frame(width: 26)
            Text(text)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.tertiary)
            }
        }
        .foregroundStyle(Palette.text)
    }
}


/// All live/waiting work across bots (the Work button sheet, §3.6).
/// Closes itself when there is nothing left to show.
struct AllWorkView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private var workingBots: [Bot] {
        store.connector.mirror.bots.filter { !$0.workSections.isIdle }
    }

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("工作")) {
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(workingBots) { bot in
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                dismiss()
                                store.openChat(botId: bot.id)
                            } label: {
                                HStack(spacing: 8) {
                                    BotAvatar(bot: bot, members: bot.members.compactMap { store.connector.mirror.bot(id: $0) }, size: 22)
                                    Text(bot.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Palette.text)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Palette.tertiary)
                                }
                                .padding(.leading, 2)
                            }
                            .buttonStyle(.plain)
                            WorkTimeline(bot: bot, mode: .plain, outlined: true, onAction: { task, action in
                                perform(bot: bot, task: task, action: action)
                            }, onOpen: { _ in
                                dismiss()
                                store.openChat(botId: bot.id)
                            })
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(Palette.background)
        .onAppear { if workingBots.isEmpty { dismiss() } }
        .onChange(of: workingBots.map(\.id)) { _, _ in
            if workingBots.isEmpty { dismiss() }
        }
    }

    private func perform(bot: Bot, task: WorkTask, action: WorkAction) {
        guard let api = store.connector.api else { return }
        Task {
            do {
                switch action {
                case .stop:
                    try await api.stopWork(botId: bot.id, taskId: task.id)
                case .cutIn:
                    if let first = bot.workSections.waiting.first {
                        try await api.workCutIn(botId: bot.id, taskId: task.id, insteadOf: first.id)
                    }
                case .first:
                    try await api.work(method: "workFirst", botId: bot.id, taskId: task.id)
                case .drop:
                    try await api.work(method: "dropWork", botId: bot.id, taskId: task.id)
                case .retry:
                    try await api.work(method: "retryWork", botId: bot.id, taskId: task.id)
                }
            } catch {
                // The host reports the failure in the chat; the row stays.
            }
        }
    }
}
