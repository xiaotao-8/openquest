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

/// The paired computer(s), connection state, and forget/pair actions.
struct ComputersView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var forgettingComputer: Computer?
    @State private var showingCloudLoginInfo = false

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("电脑")) {
                dismiss()
            }
            ScrollView {
                VStack(spacing: 24) {
                    if store.connector.computers.isEmpty {
                        CardSection(title: L("电脑")) {
                            CardRow {
                                Text(L("还没有配对电脑。"))
                                    .foregroundStyle(Palette.secondary)
                            }
                        }
                    } else {
                        CardSection(title: L("已配对")) {
                            ForEach(store.connector.computers) { computer in
                                computerRow(computer)
                                if computer.id != store.connector.computers.last?.id {
                                    Hairline()
                                }
                            }
                        }
                    }
                    cloudSection
                    PrimaryActionButton(title: L("配对新电脑")) {
                        dismiss()
                        store.showingPairing = true
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
            isPresented: $showingCloudLoginInfo,
            title: L("云电脑"),
            message: L("云电脑需要登录账号后连接，后续版本支持。现在可以先用配对码加自己搭的电脑。"),
            actions: [
                CodyncDialogAction(title: L("知道了")) {},
            ]
        )
    }

    /// One paired own computer: tap to make it current, forget on its own row.
    private func computerRow(_ computer: Computer) -> some View {
        let isCurrent = store.connector.computer?.id == computer.id
        return CardRow {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    guard !isCurrent else { return }
                    Task { await store.connector.selectComputer(computer) }
                } label: {
                    HStack {
                        ComputerBadge.icon(for: computer, size: 17)
                            .foregroundStyle(Palette.secondary)
                        Text(computer.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        if isCurrent {
                            Text(connectionText)
                                .font(.subheadline)
                                .foregroundStyle(connectionColor)
                            Image(systemName: "checkmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                Text(computer.urls.first ?? "")
                    .font(.caption)
                    .foregroundStyle(Palette.secondary)
                Button(L("忘记这台电脑"), role: .destructive) {
                    forgettingComputer = computer
                }
                .font(.subheadline)
                .foregroundStyle(Palette.danger)
            }
        }
    }

    /// The account's cloud computers. Display only for now: a cloud
    /// computer connects through the account sign-in, which lands later,
    /// so no online state is claimed for it.
    private var cloudSection: some View {
        CardSection(title: L("云电脑"), footer: L("一个账号最多可加 %d 台云电脑。", CloudComputer.accountLimit)) {
            ForEach(store.connector.cloudComputers) { cloud in
                CardRow {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "cloud")
                                .foregroundStyle(Palette.secondary)
                            Text(cloud.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Palette.text)
                            Spacer()
                            Text(L("未知"))
                                .font(.subheadline)
                                .foregroundStyle(Palette.warning)
                        }
                        Text(L("%@ · %d 个智能体", cloud.region, cloud.botCount))
                            .font(.caption)
                            .foregroundStyle(Palette.secondary)
                    }
                }
                if cloud.id != store.connector.cloudComputers.last?.id {
                    Hairline()
                }
            }
            Hairline()
            CardRow {
                Button(L("登录账号")) {
                    showingCloudLoginInfo = true
                }
                .foregroundStyle(Palette.text)
            }
        }
    }

    private var connectionText: String {
        switch store.connector.state {
        case .ready: return L("已连接")
        case .connecting: return L("连接中…")
        case .waiting: return L("重连中…")
        case .stopped: return L("离线")
        case .offline: return L("未连接")
        }
    }

    private var connectionColor: Color {
        switch store.connector.state {
        case .ready: return Palette.secondary
        default: return Palette.warning
        }
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
