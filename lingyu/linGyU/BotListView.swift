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
    @State private var searchText = ""
    @State private var showingNewBot = false
    @State private var showingWork = false
    @State private var showingComputers = false
    @State private var showingNewGroup = false

    private var mirror: EventMirror { store.connector.mirror }

    private var filteredBots: [Bot] {
        let bots = mirror.bots
        guard !searchText.isEmpty else { return bots }
        return bots.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $searchText, placeholder: L("搜索智能体"))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
            List {
                if filteredBots.isEmpty {
                    emptyState
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredBots) { bot in
                        BotRow(bot: bot)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(Palette.background)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingComputers = true
                } label: {
                    computerBadge
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("管理电脑"))
            }
            ToolbarItem(placement: .principal) {
                Text(connectionStateText)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 4) {
                    if mirror.workingBots.count > 0 || mirror.waitingTotal > 0 {
                        Button {
                            showingWork = true
                        } label: {
                            HStack(spacing: 4) {
                                Label(L("工作"), systemImage: "tray.full")
                                if mirror.workingBots.count > 0 {
                                    Text("\(mirror.workingBots.count)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(Palette.onAccent)
                                        .padding(.horizontal, 5)
                                        .frame(minHeight: 16)
                                        .background(Palette.accentFill, in: Capsule())
                                }
                            }
                            .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                    }
                    Menu {
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
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 36, height: 36)
                    }
                    .disabled(!store.connector.isPaired)
                }
            }
        }
        .refreshable {
            await MainActor.run {
                store.connector.disconnect()
                await store.connector.connectIfPaired()
            }
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

    private var computerBadge: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(Palette.bubbleAgent)
                .frame(width: 32, height: 32)
            Image(systemName: "desktopcomputer")
                .font(.system(size: 15))
                .foregroundStyle(Palette.secondary)
            Circle()
                .fill(isConnected ? Palette.added : Palette.warning)
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(Palette.background, lineWidth: 1.5))
        }
    }

    private var isConnected: Bool {
        if case .ready = store.connector.state { return true }
        return false
    }

    private var connectionStateText: String {
        switch store.connector.state {
        case .ready:
            return L("已连接")
        case .connecting:
            return L("连接中…")
        case .waiting:
            return L("重连中…")
        case .stopped:
            return L("离线")
        case .offline:
            return store.connector.isPaired ? L("未连接") : L("未配对")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(Palette.tertiary)
            Text(L("还没有智能体"))
                .font(.headline)
                .foregroundStyle(Palette.text)
            Text(L("新建一个智能体，给它起个名字、指一个项目。"))
                .font(.body)
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
        .padding(.top, 60)
    }
}

/// One roster row (§3.2): 46pt avatar, name + time, preview + badge.
struct BotRow: View {
    var bot: Bot
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationLink(value: bot.id) {
            HStack(spacing: 12) {
                if bot.isGroup {
                    GroupAvatarView(bot: bot, size: 46)
                } else {
                    AvatarView(bot: bot, size: 46)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        if bot.pinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(Palette.tertiary)
                        }
                        if bot.lead {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(Palette.warning)
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
                    HStack(spacing: 4) {
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

    @ViewBuilder
    private var preview: some View {
        // Preview priority (§3.3): needsYou > activity > work > lastMessage.
        if bot.needsInput {
            HStack(spacing: 4) {
                Circle()
                    .fill(Palette.warning)
                    .frame(width: 16, height: 16)
                Text(needsYouLine)
                    .font(.subheadline)
                    .foregroundStyle(Palette.warning)
                    .lineLimit(1)
            }
        } else if bot.isWorking {
            HStack(spacing: 4) {
                Circle()
                    .fill(Palette.secondary)
                    .frame(width: 13, height: 13)
                Text(bot.activity.isEmpty ? L("工作中…") : bot.activity)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
        } else if let liveWork = bot.work.first(where: { $0.isLive }) {
            Text(liveWork.title)
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
        } else if let lastMessage = bot.lastMessage, !lastMessage.isEmpty {
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

    private var needsYouLine: String {
        L("需要你确认")
    }
}

/// A group's 46pt avatar: a 2×2 grid of its members' avatars.
struct GroupAvatarView: View {
    var bot: Bot
    var size: CGFloat
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let members = bot.members.prefix(4).compactMap { store.connector.mirror.bot(id: $0) }
        let grid = Array(members) + Array(repeating: nil as Bot?, count: max(0, 4 - members.count))
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Palette.bubbleAgent)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                ForEach(grid.indices, id: \.self) { index in
                    if let member = grid[index] {
                        AvatarView(bot: member, size: (size - 8) / 2)
                    } else {
                        Color.clear.frame(width: (size - 8) / 2, height: (size - 8) / 2)
                    }
                }
            }
            .padding(4)
        }
        .frame(width: size, height: size)
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
    @State private var showingForgetDialog = false

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("电脑")) {
                dismiss()
            }
            ScrollView {
                VStack(spacing: 24) {
                    if let computer = store.connector.computer {
                        CardSection(title: L("已配对")) {
                            CardRow {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: "desktopcomputer")
                                            .foregroundStyle(Palette.secondary)
                                        Text(computer.name)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(Palette.text)
                                        Spacer()
                                        Text(connectionText)
                                            .font(.subheadline)
                                            .foregroundStyle(connectionColor)
                                    }
                                    Text(computer.urls.first ?? "")
                                        .font(.caption)
                                        .foregroundStyle(Palette.secondary)
                                }
                            }
                            Hairline()
                            CardRow {
                                Button(L("忘记这台电脑"), role: .destructive) {
                                    showingForgetDialog = true
                                }
                                .foregroundStyle(Palette.danger)
                            }
                        }
                    } else {
                        CardSection(title: L("电脑")) {
                            CardRow {
                                Text(L("还没有配对电脑。"))
                                    .foregroundStyle(Palette.secondary)
                            }
                        }
                    }
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
            isPresented: $showingForgetDialog,
            title: L("忘记这台电脑？"),
            message: L("这部手机将断开与这台电脑的连接。电脑上仍会列出这部设备，需要时请在电脑上撤销。"),
            actions: [
                CodyncDialogAction(title: L("取消")) {},
                CodyncDialogAction(title: L("忘记"), isDestructive: true) {
                    store.connector.forgetComputer()
                    dismiss()
                },
            ]
        )
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
struct AllWorkView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private var workingBots: [Bot] {
        store.connector.mirror.bots.filter { $0.isWorking || $0.waiting > 0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("工作")) {
                dismiss()
            }
            List {
                ForEach(workingBots) { bot in
                    Button {
                        dismiss()
                        store.openChat(botId: bot.id)
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(bot: bot, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bot.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Palette.text)
                                Text(bot.needsInput ? L("需要你确认") : (bot.activity.isEmpty ? L("工作中…") : bot.activity))
                                    .font(.subheadline)
                                    .foregroundStyle(bot.needsInput ? Palette.warning : Palette.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if bot.waiting > 0 {
                                UnreadBadge(count: bot.waiting, waiting: true)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.background)
        }
        .background(Palette.background)
    }
}
