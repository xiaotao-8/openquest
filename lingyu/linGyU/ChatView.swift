import SwiftUI
import UIKit

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
    @State private var didInitialScroll = false
    @State private var showingMiniWindow = false
    @State private var miniWindowTitle = ""
    @State private var errorMessage: String?
    @State private var showingTrace = false
    @State private var didLoadHistory = false
    @State private var showingWork = false
    @State private var showingStopDialog = false
    @State private var showingCall = false
    @State private var didHandleCallPreview = false
    @State private var shareImage: UIImage?
    @State private var shareLog: String?
    @State private var showingShareSheet = false
    @State private var copiedSessionId = false
    @State private var didHandleCandidatePreview = false

    private var mirror: EventMirror { store.connector.mirror }
    private var bot: Bot? { mirror.bot(id: botId) }

    /// The timeline: chat entries plus tool-call rows and call lines;
    /// thought/plan entries live in the working steps / trace, not the
    /// main timeline.
    private var timeline: [Entry] {
        mirror.entries(for: botId).filter { entry in
            entry.isChat || entry.kind == "tool" || entry.kind == "call"
        }
    }

    private var chatEntries: [Entry] {
        timeline.filter { $0.isChat }
    }

    var body: some View {
        if let bot {
            messageList(bot: bot)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 6) {
                        if store.incognitoBotId == botId {
                            HStack(spacing: 6) {
                                Image(systemName: "lock")
                                    .font(.caption)
                                Text(L("私密会话 · 本机不留存，内容仍经过电脑端处理"))
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                        }
                        if !bot.workSections.isIdle {
                            WorkCapsule(bot: bot, onStop: { showingStopDialog = true }, onTap: { showingWork = true })
                        }
                        Composer(
                            bot: bot,
                            sessions: mirror.bots,
                            text: $draftText,
                            isWorking: bot.isWorking,
                            isOnline: isOnline,
                            onSend: send,
                            onStop: stop,
                            // No voice call is speaking in Phase 1, so no
                            // Interrupt state; the original wires this only
                            // while a call is speaking.
                            onInterrupt: nil,
                            onCall: { showingCall = true }
                        )
                    }
                }
                .background(Palette.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                titleButton
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 20) {
                    Button {
                        showingCall = true
                    } label: {
                        Image(systemName: "phone")
                            .font(.system(size: 18, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("语音通话"))
                    Button {
                        showingFind = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("在对话中查找"))
                }
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
        .codyncSheet(isPresented: $showingWork) {
            AllWorkView()
        }
        .codyncSheet(isPresented: $showingCall) {
            CallView(bot: bot, store: store, onEnd: endCall)
        }
        .sheet(isPresented: $showingShareSheet) {
            ActivityShareView(items: shareSheetItems)
        }
        .overlay(alignment: .top) {
            if copiedSessionId {
                Text(L("已复制会话 ID"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Palette.bubbleAgent, in: Capsule())
                    .padding(.top, 8)
            }
        }
        .stopWorkDialog(isPresented: $showingStopDialog) {
            Task {
                try? await store.connector.api?.stopWork(botId: botId, taskId: bot.workSections.stoppable?.id)
            }
        }
        .onAppear {
            loadDraft()
            if !didHandleCandidatePreview, case .seeded(let options) = store.previewMode, options.candidates {
                didHandleCandidatePreview = true
                draftText = "@"
            }
            if !didHandleCallPreview, case .seeded(let options) = store.previewMode, options.call {
                didHandleCallPreview = true
                showingCall = true
            }
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
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    if let bot {
                        BotAvatar(bot: bot, members: bot.members.compactMap { mirror.bot(id: $0) }, size: 22)
                        Text(bot.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 6) {
                    Group {
                        if isConnecting {
                            Spinner(size: 8)
                        } else {
                            Image(systemName: connectionIcon)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    .frame(width: 12)
                    Text(connectionText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .contextActions { sessionMenuItems() }
    }

    // MARK: - Session menu

    /// Long-press the title for the session menu (FishPocket
    /// SessionTitleMenu). The title tap still opens the bot details
    /// and the phone/find buttons do not move: the menu takes no new
    /// space. Rename/fork/archive have no host method (HostAPI has no
    /// session rename, fork, or archive call), so they stay visible
    /// and disabled with the reason in the row instead of pretending
    /// to work. The session id is the bot id: one chat is one bot.
    private func sessionMenuItems() -> [MenuItem] {
        guard let bot else { return [] }
        return [
            MenuItem(L("重命名 · 电脑端暂不支持"), icon: "lock", enabled: false) {},
            MenuItem(L("分叉会话 · 电脑端暂不支持"), icon: "lock", enabled: false) {},
            MenuItem(L("归档会话 · 电脑端暂不支持"), icon: "lock", enabled: false) {},
            MenuItem(L("分享为图片"), icon: "photo") { shareAsImage(bot: bot) },
            MenuItem(L("导出日志"), icon: "square.and.arrow.up") { exportLog(bot: bot) },
            MenuItem(L("复制会话 ID"), icon: "doc.on.doc") { copySessionId() },
        ]
    }

    private var shareSheetItems: [Any] {
        if let shareImage { return [shareImage] }
        if let shareLog { return [shareLog] }
        return []
    }

    private func shareAsImage(bot: Bot) {
        shareLog = nil
        shareImage = SessionShareImageRenderer.render(botName: bot.name, entries: timeline, authorName: { authorBot(for: $0)?.name ?? bot.name })
        showingShareSheet = true
    }

    private func exportLog(bot: Bot) {
        shareImage = nil
        shareLog = SessionShareLog.text(botName: bot.name, sessionId: bot.id, entries: timeline, authorName: { authorBot(for: $0)?.name ?? bot.name })
        showingShareSheet = true
    }

    private func copySessionId() {
        UIPasteboard.general.string = botId
        copiedSessionId = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { copiedSessionId = false }
        }
    }

    private var isOnline: Bool {
        if case .ready = store.connector.state { return true }
        return false
    }

    /// While (re)connecting the subtitle shows a spinner, not an icon
    /// (original ChatView.connectionSubtitle).
    private var isConnecting: Bool {
        switch store.connector.state {
        case .connecting, .waiting: return true
        default: return false
        }
    }

    /// By route (original connectionSymbol): relay → cloud, direct → wifi,
    /// online with no route → network; offline → wifi.slash. The route is
    /// recorded as "direct" on hello (this build has no relay transport);
    /// the Spinner above covers connecting/waiting.
    private var connectionIcon: String {
        switch store.connector.state {
        case .ready:
            switch store.connector.computer?.route {
            case "relay": return "cloud"
            case "direct": return "wifi"
            default: return "network"
            }
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
                            Spacer()
                        }
                        .padding(.vertical, 14)
                    }
                    if timeline.isEmpty {
                        IntroCard(bot: bot, members: bot.members.compactMap { mirror.bot(id: $0) })
                            .padding(.top, 40)
                    }
                    ForEach(Array(timeline.enumerated()), id: \.element.id) { index, entry in
                        let previous = index > 0 ? timeline[index - 1] : nil
                        if index == 0 || (previous.map { entry.createdAt - $0.createdAt > 3600 * 1000 } ?? false) {
                            TimeSeparatorRow(millis: entry.createdAt)
                        }
                        MessageRow(
                            entry: entry,
                            bot: bot,
                            isGroupHead: isGroupHead(index: index),
                            author: authorBot(for: entry),
                            onResend: resend,
                            onDelete: deleteEntry,
                            onCancel: cancelEntry,
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
                            .padding(.top, 6)
                    }
                    Color.clear
                        .frame(height: 8)
                        .id("bottom")
                }
                .padding(.horizontal, 16)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.visibleRect.maxY >= geometry.contentSize.height - 100
            } action: { _, atBottom in
                isAtBottom = atBottom
            }
            .onChange(of: timeline.count) { _, _ in
                // Opening a chat must land on the latest message: the list
                // starts at the top and the geometry probe reports
                // not-at-bottom before any count change arrives, so without
                // this first jump new messages never scroll into view
                // (the live-approval screenshots kept showing old history).
                if !didInitialScroll {
                    didInitialScroll = true
                    proxy.scrollTo("bottom", anchor: .bottom)
                } else if isAtBottom {
                    withAnimation(.easeOut(duration: 0.24)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .onChange(of: timeline.contains(where: { $0.isWaitingCard })) { _, hasCard in
                // A waiting approval card is the one thing the user must
                // see: a streaming reply grows the last entry without
                // changing the count, so the count watcher never fires for
                // it and the card can land below the fold (Index 30's
                // live screenshots showed the diag but not the card).
                if hasCard {
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

    /// The bot that spoke an entry (group chats): the author, else the chat bot.
    private func authorBot(for entry: Entry) -> Bot? {
        mirror.bot(id: entry.data.author ?? entry.botId)
    }

    /// Drops a failed local message from the timeline.
    private func deleteEntry(_ entry: Entry) {
        guard let nonce = entry.data.clientNonce else { return }
        mirror.removeLocalEntry(botId: entry.botId, clientNonce: nonce)
    }

    /// Cancels a queued local message (it stays as "not sent — stopped").
    private func cancelEntry(_ entry: Entry) {
        guard let nonce = entry.data.clientNonce else { return }
        mirror.updateLocalEntry(botId: entry.botId, clientNonce: nonce, status: "cancelled")
    }

    // MARK: - Call record

    /// Writes a finished call into the chat as one titled line
    /// ("通话 · 00:16") holding the call's transcript. Local only: the
    /// host never saw the call (its voice methods need the vault), so
    /// there is no host row to echo it back.
    private func endCall(lines: [CallLine], seconds: Int) {
        guard !lines.isEmpty || seconds > 0 else { return }
        let callId = UUID().uuidString
        guard let entry = makeCallEntry(callId: callId, seconds: seconds, lines: lines) else { return }
        mirror.addLocalEntry(entry)
    }

    private func makeCallEntry(callId: String, seconds: Int, lines: [CallLine]) -> Entry? {
        // One line per turn, "user"/"agent" + a unit separator + the text:
        // the separator never appears in typed or transcribed text, so the
        // row can split it back without guessing.
        let transcript = lines.map { line in
            "\(line.speaker.rawValue)\u{1F}\(line.text)"
        }.joined(separator: "\n")
        let dict: [String: Any] = [
            "id": "local-call-\(callId)",
            "seq": 0,
            "botId": botId,
            "rev": 0,
            "kind": "call",
            "turn": 0,
            "data": [
                "text": transcript,
                "title": L("通话 · %d:%02d", seconds / 60, seconds % 60),
                "call": callId,
                "callSeconds": seconds,
                "status": "sent",
            ],
            "createdAt": Int64(Date().timeIntervalSince1970 * 1000),
            "updatedAt": Int64(Date().timeIntervalSince1970 * 1000),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        return entry
    }

    // MARK: - Drafts

    private var draftKey: String { "cn.lingyu.draft.\(botId)" }

    private func loadDraft() {
        // Incognito chats never load (or keep) a draft on this phone.
        if store.incognitoBotId == botId {
            draftText = ""
            return
        }
        draftText = UserDefaults.standard.string(forKey: draftKey) ?? ""
    }

    private func saveDraft() {
        if store.incognitoBotId == botId { return }
        UserDefaults.standard.set(draftText, forKey: draftKey)
    }
}

/// One timeline row: user bubble, agent bubble, card, notice, or tool row.
struct MessageRow: View {
    var entry: Entry
    var bot: Bot
    var isGroupHead: Bool
    var author: Bot?
    var onResend: (Entry) -> Void
    var onDelete: (Entry) -> Void
    var onCancel: (Entry) -> Void
    var onShowBrowser: (String) -> Void

    var body: some View {
        switch entry.kind {
        case "user":
            UserBubble(entry: entry, onResend: { onResend(entry) }, onDelete: { onDelete(entry) }, onCancel: { onCancel(entry) })
        case "agent":
            AgentBubble(entry: entry, bot: bot, isGroupHead: isGroupHead, author: author)
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
        case "call":
            CallLineRow(entry: entry)
        case "view":
            if entry.isViewCard {
                ViewCardView(entry: entry, bot: bot)
            }
        case "learning":
            if entry.isLearningCard {
                LearningCard(entry: entry, bot: bot)
            }
        default:
            EmptyView()
        }
    }
}

struct UserBubble: View {
    var entry: Entry
    var onResend: () -> Void
    var onDelete: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Spacer(minLength: 56)
                VStack(alignment: .leading, spacing: 4) {
                    if let attachments = entry.data.attachments, !attachments.isEmpty {
                        ForEach(attachments, id: \.id) { attachment in
                            HStack(spacing: 6) {
                                Image(systemName: AttachmentIcon.symbol(attachment.name))
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
                .background(Palette.bubbleUser, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            statusRow
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// Timestamp (always, the message's own event time) + delivery status
    /// (when it isn't the default "sent" state), in one small row under
    /// the bubble, right-aligned with it.
    private var statusRow: some View {
        HStack(spacing: 6) {
            Text(RelativeTime.clock(entry.createdAt))
                .font(.caption2)
                .foregroundStyle(Palette.tertiary)
            statusLabel
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch entry.data.status {
        case "sending":
            Text(L("发送中…"))
                .font(.caption2)
                .foregroundStyle(Palette.tertiary)
        case "failed":
            HStack(spacing: 10) {
                Text(L("发送失败"))
                    .foregroundStyle(Palette.danger)
                Button(L("重发"), systemImage: "arrow.clockwise", action: onResend)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel(L("重发"))
                Button(L("删除"), systemImage: "trash", action: onDelete)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel(L("删除"))
            }
            .buttonStyle(.plain)
            .font(.caption2.bold())
        case "cancelled":
            Text(L("未发送，已停止"))
                .font(.caption2)
                .foregroundStyle(Palette.tertiary)
        case "waiting", "held":
            HStack(spacing: 10) {
                Text(L("等待电脑上线"))
                    .foregroundStyle(Palette.tertiary)
                Button(L("取消"), systemImage: "xmark.circle", action: onCancel)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel(L("取消发送"))
            }
            .buttonStyle(.plain)
            .font(.caption2)
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
    var isGroupHead: Bool
    var author: Bot?
    @EnvironmentObject private var store: AppStore

    /// The message's first line, for use as a Feed/Idea title.
    private var shortTitle: String {
        let text = entry.data.text ?? ""
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        return String(firstLine.prefix(40))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if bot.isGroup, isGroupHead, let author {
                AuthorLabel(author: author)
            }
            if entry.data.thread != nil {
                WorkThreadLine(data: entry.data)
                    .padding(.leading, 4)
            }
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    if (entry.data.text ?? "").contains("```schemaJson") {
                        GenUIMessageView(text: entry.data.text ?? "")
                    } else {
                        Text(markdownText)
                            .font(.body)
                            .foregroundStyle(Palette.text)
                            .textSelection(.enabled)
                    }
                }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Palette.bubbleAgent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = entry.data.text ?? ""
                        } label: {
                            Label(L("复制"), systemImage: "doc.on.doc")
                        }
                        Button {
                            store.feed.add(title: shortTitle, body: entry.data.text ?? "", category: L("对话"), source: "chat")
                        } label: {
                            Label(L("保存到简报"), systemImage: "newspaper")
                        }
                        Button {
                            store.ideas.add(title: shortTitle, category: L("对话"), source: "chat")
                        } label: {
                            Label(L("保存为建议"), systemImage: "lightbulb")
                        }
                    }
                Spacer(minLength: 40)
            }
            Text(RelativeTime.clock(entry.createdAt))
                .font(.caption2)
                .foregroundStyle(Palette.tertiary)
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

/// The author line above a group message: the speaking bot's avatar and
/// name in its own colour.
struct AuthorLabel: View {
    var author: Bot

    var body: some View {
        HStack(spacing: 6) {
            AvatarView(bot: author, size: 26)
            Text(author.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.avatarColor(named: author.avatarColor))
        }
    }
}

struct NoticeRow: View {
    var entry: Entry

    var body: some View {
        if entry.data.style == "error" {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.danger)
                    Text(entry.data.text ?? "")
                        .font(.footnote)
                        .foregroundStyle(Palette.text)
                }
                WorkThreadLine(data: entry.data)
                    .padding(.leading, 4)
            }
            .padding(12)
            .background(Palette.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack {
                Spacer()
                Text(entry.data.text ?? "")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
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

    /// The original ToolRow icon map (TraceView): read → doc.text,
    /// edit → pencil, delete → trash, move → arrow.right.doc.on.clipboard,
    /// search → magnifyingglass, execute → terminal, think → brain,
    /// fetch → globe; anything else (incl. browser) → wrench.and.screwdriver.
    private var toolIcon: String {
        switch entry.data.toolKind {
        case "read": return "doc.text"
        case "edit": return "pencil"
        case "delete": return "trash"
        case "move": return "arrow.right.doc.on.clipboard"
        case "search": return "magnifyingglass"
        case "execute": return "terminal"
        case "think": return "brain"
        case "fetch": return "globe"
        default: return "wrench.and.screwdriver"
        }
    }
}

/// A finished call, as one titled line ("通话 · 00:16") next to the
/// tool-call rows. Tapping it opens the call's transcript.
struct CallLineRow: View {
    var entry: Entry
    @State private var expanded = false

    /// The transcript, split back from the entry's text: one line per
    /// turn, "user"/"agent" + unit separator + the text.
    private var turns: [(speaker: String, text: String)] {
        (entry.data.text ?? "").components(separatedBy: "\n").compactMap { line in
            guard let separator = line.firstIndex(of: "\u{1F}") else { return nil }
            let speaker = String(line[..<separator])
            let text = String(line[line.index(after: separator)...])
            guard !text.isEmpty else { return nil }
            return (speaker, text)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "phone")
                        .font(.system(size: 16))
                        .foregroundStyle(Palette.secondary)
                    Text(entry.data.title ?? L("通话"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.tertiary)
                }
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(turns.enumerated()), id: \.offset) { _, turn in
                        HStack(alignment: .top, spacing: 8) {
                            Text(turn.speaker == "user" ? L("你") : L("智能体"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.secondary)
                            Text(turn.text)
                                .font(.subheadline)
                                .foregroundStyle(Palette.text)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
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

/// The bot's current activity and elapsed time; with thinking details on
/// (Settings), a tap unfolds the turn's steps.
struct WorkingIndicator: View {
    var bot: Bot
    @EnvironmentObject private var store: AppStore
    @State private var stepsExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var open: Bool { store.showThinkingDetails && stepsExpanded }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            if store.showThinkingDetails {
                Button {
                    withAnimation(Motion.reduced(Motion.layout, reduceMotion)) {
                        stepsExpanded.toggle()
                    }
                } label: {
                    status.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(L(open ? "隐藏步骤" : "显示步骤"))
                .accessibilityValue(L(open ? "已展开" : "已折叠"))
            } else {
                status
            }
            if open {
                WorkingSteps(botId: bot.id)
                    .padding(.top, 12)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: open ? .infinity : nil, alignment: .leading)
        .background(Palette.bubbleAgent, in: shape)
        // Folding steps never cross the pill's edge.
        .clipShape(shape)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 40)
    }

    private var status: some View {
        HStack(spacing: 8) {
            ThinkingOrb(
                state: bot.needsInput ? .listening : .working,
                size: 16,
                color: bot.needsInput ? Palette.warning : Palette.secondary
            )
            Text(bot.needsInput ? L("需要你确认") : (bot.activity.isEmpty ? L("工作中…") : bot.activity))
                .font(.subheadline)
                .foregroundStyle(bot.needsInput ? Palette.warning : Palette.secondary)
                .lineLimit(1)
                .frame(maxWidth: open ? .infinity : nil, alignment: .leading)
            if let startedAt = bot.startedAt {
                Text(Date(timeIntervalSince1970: TimeInterval(startedAt) / 1000), style: .timer)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Palette.tertiary)
            }
            if store.showThinkingDetails {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.tertiary)
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
        }
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
            VStack(alignment: .leading, spacing: 10) {
                if steps.isEmpty {
                    Text(L("还没有内容。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.tertiary)
                } else {
                    ForEach(steps.suffix(20)) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: entry.kind == "tool" ? "wrench.and.screwdriver" : "brain")
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
    var members: [Bot]

    var body: some View {
        VStack(spacing: 12) {
            BotAvatar(bot: bot, members: members, size: 72)
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
            if bot.isGroup {
                Text(L("大家轮流回答。@ 某个智能体，只问它一个。"))
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
        .padding(.horizontal, 24)
    }

    private var agentSubtitle: String {
        "\(bot.backend) · \(bot.folderDisplay)"
    }

    private var groupSubtitle: String {
        let names = members.map(\.name).joined(separator: " · ")
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
