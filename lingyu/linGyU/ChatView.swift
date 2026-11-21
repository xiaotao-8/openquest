import SwiftUI

/// The chat page (§4): lazy message list, bubbles, inline cards, tool-call
/// rows, WorkingIndicator, FindBar, Composer, MiniWindow. The list is a
/// lazy ScrollView — never a non-lazy TimelineList (the lag cause).
struct ChatView: View {
    var botId: String
    @EnvironmentObject private var store: AppStore
    @State private var draftText = ""
    @State private var showingFind = false
    @State private var findText = ""
    @State private var findIndex = 0
    @State private var loadingEarlier = false
    @State private var hasMoreEarlier = true
    @State private var isAtBottom = true
    @State private var showingMiniWindow = false
    @State private var miniWindowTitle = ""
    @State private var errorMessage: String?
    @State private var showingTrace = false
    @State private var didLoadHistory = false

    private var mirror: EventMirror { store.connector.mirror }
    private var bot: Bot? { mirror.bot(id: botId) }

    /// The timeline: chat entries plus tool-call rows; thought/plan entries
    /// live in the working steps / trace, not the main timeline.
    private var timeline: [Entry] {
        mirror.entries(for: botId).filter { entry in
            entry.isChat || entry.kind == "tool"
        }
    }

    private var chatEntries: [Entry] {
        timeline.filter { $0.isChat }
    }

    var body: some View {
        if let bot {
            VStack(spacing: 0) {
                messageList(bot: bot)
                Composer(
                    bot: bot,
                    text: $draftText,
                    isWorking: bot.isWorking,
                    isOnline: isOnline,
                    onSend: send,
                    onStop: stop
                )
            }
            .background(Palette.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                titleButton
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingFind = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("在对话中查找"))
            }
        }
        .overlay(alignment: .top) {
            if showingFind {
                FindBar(
                    text: $findText,
                    matchText: findMatchText,
                    onClose: { showingFind = false; findText = "" },
                    onPrevious: { moveFind(by: -1) },
                    onNext: { moveFind(by: 1) }
                )
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
        }
        .overlay {
            if showingMiniWindow {
                MiniWindow(title: miniWindowTitle, onClose: { showingMiniWindow = false })
            }
        }
        .onAppear {
            loadDraft()
            if !didLoadHistory {
                didLoadHistory = true
                loadEarlier()
            }
            Task {
                try? await store.connector.api?.markRead(botId: botId)
            }
        }
        .onDisappear {
            saveDraft()
        }
        .onChange(of: draftText) { _, _ in
            saveDraft()
        }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 44, weight: .ultraLight))
                    .foregroundStyle(Palette.tertiary)
                Text(L("找不到这个智能体"))
                    .font(.headline)
                    .foregroundStyle(Palette.text)
                Text(L("它可能已被删除。"))
                    .font(.body)
                    .foregroundStyle(Palette.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background)
        }
    }

    // MARK: - Title

    private var titleButton: some View {
        Button {
            store.detailBotId = botId
        } label: {
            VStack(spacing: 1) {
                HStack(spacing: 7) {
                    if let bot {
                        if bot.isGroup {
                            GroupAvatarView(bot: bot, size: 22)
                        } else {
                            AvatarView(bot: bot, size: 22)
                        }
                        Text(bot.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 3) {
                    Image(systemName: connectionIcon)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                    Text(connectionText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var isOnline: Bool {
        if case .ready = store.connector.state { return true }
        return false
    }

    private var connectionIcon: String {
        switch store.connector.state {
        case .ready: return "wifi"
        case .connecting, .waiting: return "network"
        case .stopped, .offline: return "wifi.slash"
        }
    }

    private var connectionText: String {
        switch store.connector.state {
        case .ready: return L("已连接")
        case .connecting: return L("连接中")
        case .waiting: return L("重连中…")
        case .stopped, .offline: return L("离线")
        }
    }

    // MARK: - Message list

    private func messageList(bot: Bot) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if loadingEarlier {
                        HStack {
                            Spacer()
                            Spinner(size: 14)
                            Text(L("正在加载更早的消息"))
                                .font(.footnote)
                                .foregroundStyle(Palette.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    }
                    if timeline.isEmpty {
                        IntroCard(bot: bot)
                            .padding(.top, 40)
                    }
                    ForEach(Array(timeline.enumerated()), id: \.element.id) { index, entry in
                        let previous = index > 0 ? timeline[index - 1] : nil
                        if let previous, entry.createdAt - previous.createdAt > 3600 * 1000 {
                            TimeSeparatorRow(millis: entry.createdAt)
                        }
                        MessageRow(
                            entry: entry,
                            bot: bot,
                            isGroupHead: isGroupHead(index: index),
                            onResend: resend,
                            onShowBrowser: { title in
                                miniWindowTitle = title
                                showingMiniWindow = true
                            }
                        )
                        .id(entry.id)
                        .padding(.top, groupTopPadding(index: index))
                    }
                    if bot.isWorking {
                        WorkingIndicator(bot: bot)
                            .padding(.top, 12)
                    }
                    Color.clear
                        .frame(height: 8)
                        .id("bottom")
                }
                .padding(.horizontal, 16)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.viewportSize.height >= geometry.contentSize.height - 100
            } action: { _, atBottom in
                isAtBottom = atBottom
            }
            .onChange(of: timeline.count) { _, _ in
                if isAtBottom {
                    withAnimation(.easeOut(duration: 0.24)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .onChange(of: findIndex) { _, _ in
                if let match = currentFindMatch {
                    withAnimation {
                        proxy.scrollTo(match.id, anchor: .center)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !isAtBottom {
                    Button {
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.text)
                            .frame(width: 36, height: 36)
                            .background(Palette.bubbleAgent, in: Circle())
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func isGroupHead(index: Int) -> Bool {
        guard index > 0 else { return true }
        let entry = timeline[index]
        let previous = timeline[index - 1]
        let entryAuthor = entry.data.author ?? entry.botId
        let previousAuthor = previous.data.author ?? previous.botId
        return entryAuthor != previousAuthor || entry.kind != previous.kind
    }

    private func groupTopPadding(index: Int) -> CGFloat {
        isGroupHead(index: index) ? 12 : 4
    }

    // MARK: - Find

    private var findMatches: [Entry] {
        guard !findText.isEmpty else { return [] }
        return chatEntries.filter { ($0.data.text ?? "").localizedCaseInsensitiveContains(findText) }
    }

    private var currentFindMatch: Entry? {
        guard !findMatches.isEmpty else { return nil }
        return findMatches[min(max(findIndex, 0), findMatches.count - 1)]
    }

    private var findMatchText: String {
        guard !findText.isEmpty else { return "" }
        guard !findMatches.isEmpty else { return L("无匹配") }
        return "\(findIndex + 1)/\(findMatches.count)"
    }

    private func moveFind(by delta: Int) {
        guard !findMatches.isEmpty else { return }
        findIndex = (findIndex + delta + findMatches.count) % findMatches.count
    }

    // MARK: - History / send / stop

    private func loadEarlier() {
        guard let api = store.connector.api, hasMoreEarlier, !loadingEarlier else { return }
        loadingEarlier = true
        let beforeSeq = mirror.entries(for: botId).map(\.seq).min() ?? 0
        Task {
            do {
                let page = try await api.history(botId: botId, beforeSeq: beforeSeq, limit: 100)
                await MainActor.run {
                    mirror.mergeHistory(page)
                    hasMoreEarlier = page.count >= 100
                    loadingEarlier = false
                }
            } catch {
                await MainActor.run {
                    loadingEarlier = false
                }
            }
        }
    }

    private func send(text: String, attachments: [PendingAttachment]) {
        guard let api = store.connector.api else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        let nonce = UUID().uuidString
        let local = Entry(localText: trimmed, botId: botId, clientNonce: nonce)
        mirror.addLocalEntry(local)
        Task {
            do {
                var uploadIds: [String] = []
                for attachment in attachments {
                    let id = try await api.upload(botId: botId, name: attachment.name, data: attachment.data)
                    uploadIds.append(id)
                }
                _ = try await api.send(botId: botId, text: trimmed, clientNonce: nonce, attachments: uploadIds.isEmpty ? nil : uploadIds)
            } catch {
                await MainActor.run {
                    mirror.updateLocalEntry(botId: botId, clientNonce: nonce, status: "failed")
                }
            }
        }
    }

    private func stop() {
        Task {
            try? await store.connector.api?.stop(botId: botId)
        }
    }

    /// Resends a failed message with the same clientNonce (the host dedupes
    /// by nonce, so a retry never double-sends).
    private func resend(entry: Entry) {
        guard let api = store.connector.api,
              let nonce = entry.data.clientNonce,
              let text = entry.data.text else { return }
        mirror.updateLocalEntry(botId: botId, clientNonce: nonce, status: "sending")
        Task {
            do {
                _ = try await api.send(botId: botId, text: text, clientNonce: nonce)
            } catch {
                await MainActor.run {
                    mirror.updateLocalEntry(botId: botId, clientNonce: nonce, status: "failed")
                }
            }
        }
    }

    // MARK: - Drafts

    private var draftKey: String { "cn.lingyu.draft.\(botId)" }

    private func loadDraft() {
        draftText = UserDefaults.standard.string(forKey: draftKey) ?? ""
    }

    private func saveDraft() {
        UserDefaults.standard.set(draftText, forKey: draftKey)
    }
}

/// One timeline row: user bubble, agent bubble, card, notice, or tool row.
struct MessageRow: View {
    var entry: Entry
    var bot: Bot
    var isGroupHead: Bool
    var onResend: (Entry) -> Void
    var onShowBrowser: (String) -> Void

    var body: some View {
        switch entry.kind {
        case "user":
            UserBubble(entry: entry, onResend: { onResend(entry) })
        case "agent":
            AgentBubble(entry: entry, bot: bot)
        case "permission":
            if entry.isAskCard {
                DecisionCard(entry: entry, bot: bot)
            } else {
                PermissionCard(entry: entry, bot: bot)
            }
        case "notice":
            NoticeRow(entry: entry)
        case "tool":
            ToolCallRow(entry: entry, onShowBrowser: onShowBrowser)
        default:
            EmptyView()
        }
    }
}

struct UserBubble: View {
    var entry: Entry
    var onResend: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Spacer(minLength: 56)
                VStack(alignment: .leading, spacing: 6) {
                    if let attachments = entry.data.attachments, !attachments.isEmpty {
                        ForEach(attachments, id: \.id) { attachment in
                            HStack(spacing: 6) {
                                Image(systemName: "doc")
                                    .foregroundStyle(Palette.secondary)
                                Text(attachment.name)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.text)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Text(entry.data.text ?? "")
                        .font(.body)
                        .foregroundStyle(Palette.text)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Palette.bubbleUser, in: RoundedRectangle(cornerRadius: 18))
            }
            statusRow
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch entry.data.status {
        case "sending":
            Text(L("发送中…"))
                .font(.caption2)
                .foregroundStyle(Palette.tertiary)
        case "failed":
            HStack(spacing: 8) {
                Text(L("发送失败"))
                    .font(.caption2)
                    .foregroundStyle(Palette.danger)
                Button(L("重发"), action: onResend)
                .font(.caption2)
                .foregroundStyle(Palette.text)
            }
        case "cancelled":
            Text(L("未发送，已停止"))
                .font(.caption2)
                .foregroundStyle(Palette.tertiary)
        case "waiting", "held":
            Text(L("等待电脑上线"))
                .font(.caption2)
                .foregroundStyle(Palette.tertiary)
        case "delivering":
            Text(L("已送达电脑"))
                .font(.caption2)
                .foregroundStyle(Palette.tertiary)
        default:
            EmptyView()
        }
    }
}

struct AgentBubble: View {
    var entry: Entry
    var bot: Bot

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AvatarView(bot: bot, size: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(markdownText)
                    .font(.body)
                    .foregroundStyle(Palette.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Palette.bubbleAgent, in: RoundedRectangle(cornerRadius: 18))
            }
            Spacer(minLength: 40)
        }
    }

    private var markdownText: AttributedString {
        let text = entry.data.text ?? ""
        if let attributed = try? AttributedString(markdown: text) {
            return attributed
        }
        return AttributedString(text)
    }
}

struct NoticeRow: View {
    var entry: Entry

    var body: some View {
        HStack {
            Spacer()
            Text(entry.data.text ?? "")
                .font(.footnote)
                .foregroundStyle(entry.data.style == "error" ? Palette.danger : Palette.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

/// A tool-call row (§4.3, FishPocket-style inline summary). Browser calls
/// carry a "查看" button that floats the MiniWindow over the chat.
struct ToolCallRow: View {
    var entry: Entry
    var onShowBrowser: (String) -> Void
    @State private var expanded = false

    private var isBrowser: Bool {
        entry.data.toolKind == "browser" || entry.data.toolKind == "fetch"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: toolIcon)
                        .font(.system(size: 16))
                        .foregroundStyle(Palette.secondary)
                    Text(entry.data.title ?? L("工具调用"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    if entry.data.status == "in_progress" || entry.data.status == "pending" {
                        Spinner(size: 12)
                    }
                    Spacer()
                    if isBrowser {
                        Button(L("查看")) {
                            onShowBrowser(entry.data.title ?? L("浏览器"))
                        }
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            if expanded {
                if let command = entry.data.command {
                    CodeBox(text: command)
                }
                if let output = entry.data.output {
                    CodeBox(text: output)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var toolIcon: String {
        switch entry.data.toolKind {
        case "execute": return "terminal"
        case "edit", "delete", "move": return "doc.text"
        case "fetch", "browser": return "globe"
        case "read", "search": return "doc.magnifyingglass"
        default: return "wrench"
        }
    }
}

struct TimeSeparatorRow: View {
    var millis: Int64

    var body: some View {
        Text(RelativeTime.separator(millis))
            .font(.footnote)
            .foregroundStyle(Palette.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 18)
            .padding(.bottom, 6)
    }
}

/// The working indicator at the end of the timeline (§4.4).
struct WorkingIndicator: View {
    var bot: Bot
    @EnvironmentObject private var store: AppStore
    @State private var stepsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if store.showThinkingDetails {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        stepsExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(bot.needsInput ? Palette.warning : Palette.secondary)
                        .frame(width: 16, height: 16)
                    Text(bot.needsInput ? L("需要你确认") : (bot.activity.isEmpty ? L("工作中…") : bot.activity))
                        .font(.subheadline)
                        .foregroundStyle(bot.needsInput ? Palette.warning : Palette.secondary)
                        .lineLimit(1)
                    Spacer()
                    if store.showThinkingDetails {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.tertiary)
                            .rotationEffect(.degrees(stepsExpanded ? 90 : 0))
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!store.showThinkingDetails)
            if stepsExpanded {
                WorkingSteps(botId: bot.id)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Palette.bubbleAgent, in: RoundedRectangle(cornerRadius: 18))
        .padding(.trailing, 40)
    }
}

/// The current turn's thought/tool/plan steps (Settings → 思考详情).
struct WorkingSteps: View {
    var botId: String
    @EnvironmentObject private var store: AppStore

    private var steps: [Entry] {
        store.connector.mirror.entries(for: botId).filter { entry in
            entry.kind == "thought" || entry.kind == "tool" || entry.kind == "plan"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if steps.isEmpty {
                    Text(L("还没有内容。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.tertiary)
                } else {
                    ForEach(steps.suffix(20)) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: entry.kind == "tool" ? "wrench" : "brain")
                                .font(.caption)
                                .foregroundStyle(Palette.secondary)
                            Text(entry.data.text ?? entry.data.title ?? "")
                                .font(.subheadline)
                                .foregroundStyle(Palette.secondary)
                                .lineLimit(3)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 280)
    }
}

/// The empty-chat intro card (§4.6).
struct IntroCard: View {
    var bot: Bot

    var body: some View {
        VStack(spacing: 12) {
            AvatarView(bot: bot, size: 72)
            Text(bot.name)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Palette.text)
            Text(bot.isGroup ? groupSubtitle : agentSubtitle)
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
            if !bot.description.isEmpty {
                Text(bot.description)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
            }
            Text(L("告诉它你需要什么。完成或需要你时，你会收到通知。"))
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    private var agentSubtitle: String {
        "\(bot.backend) · \(bot.folderDisplay)"
    }

    private var groupSubtitle: String {
        let names = bot.members.joined(separator: " · ")
        return names.isEmpty ? L("群聊") : names
    }
}

struct FindBar: View {
    @Binding var text: String
    var matchText: String
    var onClose: () -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            SearchField(text: $text, placeholder: L("在对话中查找"))
            Text(matchText)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(matchText == L("无匹配") ? Palette.attention : Palette.secondary)
            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.iconButton)
            Button(action: onNext) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.iconButton)
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.iconButton)
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(Palette.bubbleAgent, in: Capsule())
    }
}
