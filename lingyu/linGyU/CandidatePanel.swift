import SwiftUI

/// What the composer is offering above the input field (FishPocket
/// CandidatePanel): "/" lists the app's slash commands, "@" lists
/// sessions and workspace files. Both lists are real data only — a
/// group with no source renders disabled with its reason, never
/// invented rows.
enum CandidateTrigger: Equatable {
    case slash(query: String)
    case mention(query: String)

    /// A trailing "@query" wins over a leading "/": the cursor is
    /// right after the "@" word, so the user is mentioning something.
    static func parse(_ text: String) -> CandidateTrigger? {
        if let query = trailingMentionQuery(in: text) { return .mention(query: query) }
        if let query = leadingSlashQuery(in: text) { return .slash(query: query) }
        return nil
    }

    /// The text after the last "@", when "@" starts the last word and
    /// the word has no space in it (the cursor is right after it).
    static func trailingMentionQuery(in text: String) -> String? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        let after = text[text.index(after: at)...]
        guard !after.contains(" "), !after.contains("\n") else { return nil }
        if at != text.startIndex {
            let before = text[text.index(before: at)]
            guard before == " " || before == "\n" else { return nil }
        }
        return String(after)
    }

    /// The text starts with "/" and the first word is still the command
    /// (no space typed yet).
    static func leadingSlashQuery(in text: String) -> String? {
        guard text.hasPrefix("/") else { return nil }
        let rest = text.dropFirst()
        guard !rest.contains(" "), !rest.contains("\n") else { return nil }
        return String(rest)
    }

    /// The range of the trailing "@query" token, for replacing it with a
    /// mention.
    static func mentionRange(in text: String) -> Range<String.Index>? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        let after = text[text.index(after: at)...]
        guard !after.contains(" "), !after.contains("\n") else { return nil }
        return at..<text.endIndex
    }
}

/// The candidate panel above the composer: at most 4 rows plus an
/// "全部" row that expands the list (scrollable, still 4 rows tall).
struct CandidatePanel: View {
    var trigger: CandidateTrigger
    var sessions: [Bot]
    @Binding var showAll: Bool
    var onSelectSession: (Bot) -> Void

    private let rowHeight: CGFloat = 52
    private let maxVisibleRows = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch trigger {
            case .slash:
                panelHeader(L("命令"))
                disabledRow(title: L("暂无斜杠命令"), reason: L("电脑端未提供命令列表"))
            case .mention(let query):
                mentionBody(query: query)
            }
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func mentionBody(query: String) -> some View {
        panelHeader(L("会话"))
        let filtered = filteredSessions(query: query)
        if filtered.isEmpty {
            disabledRow(title: L("暂无会话"), reason: nil)
        } else if showAll {
            ScrollView(showsIndicators: false) {
                sessionList(filtered: filtered)
            }
            .frame(maxHeight: CGFloat(maxVisibleRows) * rowHeight)
        } else {
            sessionList(filtered: filtered)
        }
        panelHeader(L("文件"))
        // No host file-list API exists (HostAPI has no glob/list method),
        // so there are no file rows and no folder to drill into; the
        // group stays visible with its reason instead of disappearing.
        disabledRow(title: L("电脑端未提供文件列表"), reason: nil)
    }

    private func filteredSessions(query: String) -> [Bot] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return sessions }
        return sessions.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private func sessionList(filtered: [Bot]) -> some View {
        VStack(spacing: 0) {
            let visible = showAll ? filtered : Array(filtered.prefix(maxVisibleRows))
            ForEach(visible) { session in
                Button {
                    onSelectSession(session)
                } label: {
                    sessionRow(session)
                }
                .buttonStyle(.plain)
            }
            if !showAll, filtered.count > maxVisibleRows {
                Button {
                    showAll = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.secondary)
                        Text(L("全部"))
                            .font(.subheadline)
                            .foregroundStyle(Palette.text)
                        Text("\(filtered.count)")
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: rowHeight)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sessionRow(_ session: Bot) -> some View {
        HStack(spacing: 10) {
            AvatarView(bot: session, size: 28)
            Text(session.name)
                .font(.subheadline)
                .foregroundStyle(Palette.text)
                .lineLimit(1)
            Spacer()
            if session.isGroup {
                Text(L("%d 个智能体", session.members.count))
                    .font(.caption)
                    .foregroundStyle(Palette.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: rowHeight)
    }

    private func panelHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func disabledRow(title: String, reason: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 14))
                .foregroundStyle(Palette.tertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
                if let reason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(Palette.tertiary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: reason == nil ? 44 : rowHeight)
    }
}
