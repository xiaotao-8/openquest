import SwiftUI

/// The approval card (§7.1): Codync semantics — Allow once / Always allow /
/// Deny — inside the chat. Answers via `respondPermission`; the host emits
/// the updated entry (status `answered`) as an event.
struct PermissionCard: View {
    var entry: Entry
    var bot: Bot
    @EnvironmentObject private var store: AppStore
    @State private var detailsExpanded = false
    @State private var answeringOptionId: String?
    @State private var answeredOptionKind: String?
    /// Set once this card has been auto-answered under skip-all-approvals,
    /// so it never answers twice.
    @State private var bypassAnswered = false

    private var data: EntryData { entry.data }
    private var isPending: Bool { data.status == "pending" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(titleForToolKind)
                    .font(.headline)
                    .foregroundStyle(Palette.text)
                if isPending {
                    Circle()
                        .fill(Palette.warning)
                        .frame(width: 7, height: 7)
                }
                Spacer()
            }
            if let mono = data.command ?? data.title, !mono.isEmpty {
                Text(mono)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(detailsExpanded ? nil : 3)
            }
            HStack(spacing: 4) {
                Image(systemName: "desktopcomputer")
                    .font(.caption)
                    .foregroundStyle(Palette.tertiary)
                Text(runsOnLine)
                    .font(.caption)
                    .foregroundStyle(Palette.tertiary)
            }
            WorkThreadLine(data: data)
            if hasDetails {
                detailsSection
            }
            if isPending {
                answerButtons
            } else {
                Text(outcomeText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Palette.bubbleAgent, in: RoundedRectangle(cornerRadius: 22))
        .padding(.trailing, 40)
        .onAppear { autoAnswerIfBypassed() }
        .onChange(of: store.bypassAllApprovals) { _, _ in autoAnswerIfBypassed() }
    }

    /// Skip-all-approvals: a pending approval card is answered Allow-once
    /// by itself instead of waiting on the user. Ask cards never reach
    /// this view (they render as DecisionCard), so questions are never
    /// auto-answered.
    private func autoAnswerIfBypassed() {
        guard store.bypassAllApprovals, isPending, !bypassAnswered,
              answeringOptionId == nil,
              let api = store.connector.api else { return }
        let option = answerOptions.first(where: { $0.kind == "allow_once" })
            ?? answerOptions.first
        guard let option else { return }
        bypassAnswered = true
        answeringOptionId = option.optionId
        Task {
            do {
                try await api.respondPermission(entryId: entry.id, optionId: option.optionId)
                answeredOptionKind = option.kind
            } catch {
                answeringOptionId = nil
                bypassAnswered = false
            }
        }
    }

    private var titleForToolKind: String {
        switch data.toolKind {
        case "execute":
            return L("想运行一条命令")
        case "edit", "delete", "move":
            return L("想修改文件")
        case "fetch":
            return L("想访问网络")
        case "read", "search":
            return L("想读取文件")
        default:
            return L("想使用一个工具")
        }
    }

    private var runsOnLine: String {
        let computerName = store.connector.computer?.name ?? ""
        let folder = bot.folderDisplay
        return L("运行于 %@ · %@", computerName, folder)
    }

    private var hasDetails: Bool {
        data.command != nil || data.detail != nil || (data.diffs?.isEmpty == false)
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    detailsExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(L("详情"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.secondary)
                        .rotationEffect(.degrees(detailsExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)
            if detailsExpanded {
                if let command = data.command {
                    CodeBox(text: command)
                }
                if let detail = data.detail {
                    CodeBox(text: String(detail.prefix(2000)))
                }
                if let diffs = data.diffs {
                    ForEach(diffs, id: \.path) { diff in
                        DiffView(diff: diff)
                    }
                }
            }
        }
    }

    private var answerButtons: some View {
        VStack(spacing: 0) {
            ForEach(answerOptions, id: \.optionId) { option in
                Button {
                    answer(option: option)
                } label: {
                    HStack {
                        Text(option.name)
                            .font(option.kind == "allow_once" ? .body.weight(.semibold) : .body)
                            .foregroundStyle(option.kind.hasPrefix("reject") ? Palette.danger : Palette.text)
                        Spacer()
                        if answeringOptionId == option.optionId {
                            Spinner(size: 14)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(answeringOptionId != nil)
                .opacity(answeringOptionId != nil && answeringOptionId != option.optionId ? 0.4 : 1)
                if option.optionId != answerOptions.last?.optionId {
                    Hairline()
                }
            }
        }
        .background(Palette.background, in: RoundedRectangle(cornerRadius: 14))
        .padding(.top, 4)
    }

    /// The three Codync rows, in fixed order. Falls back to the standard
    /// three when the entry carries no options.
    private var answerOptions: [PermissionOption] {
        if let options = data.options, !options.isEmpty {
            return options
        }
        return [
            PermissionOption(optionId: "allow_once", name: L("仅允许一次"), kind: "allow_once"),
            PermissionOption(optionId: "allow_always", name: L("始终允许"), kind: "allow_always"),
            PermissionOption(optionId: "deny", name: L("拒绝"), kind: "reject_once"),
        ]
    }

    private var outcomeText: String {
        if let kind = answeredOptionKind {
            switch kind {
            case "allow_once": return L("仅允许一次")
            case "allow_always": return L("始终允许")
            case "reject_once": return L("已拒绝")
            case "reject_always": return L("始终拒绝")
            default: return L("已回答")
            }
        }
        switch data.status {
        case "answered":
            if let selected = data.selected {
                return selected
            }
            return L("已回答")
        case "cancelled":
            return L("已取消")
        case "expired":
            return L("已过期，智能体已继续")
        default:
            return L("已回答")
        }
    }

    private func answer(option: PermissionOption) {
        guard let api = store.connector.api else { return }
        answeringOptionId = option.optionId
        Task {
            do {
                try await api.respondPermission(entryId: entry.id, optionId: option.optionId)
                answeredOptionKind = option.kind
            } catch {
                answeringOptionId = nil
            }
        }
    }
}

/// Which work thread a card belongs to: "Work · {title}", with a clock.
/// Hidden when the entry has no thread.
struct WorkThreadLine: View {
    let data: EntryData

    var body: some View {
        if let thread = data.thread, !thread.title.isEmpty {
            Label(L("工作") + " · " + thread.title, systemImage: "clock")
                .font(.caption)
                .foregroundStyle(Palette.tertiary)
                .lineLimit(1)
        }
    }
}

struct CodeBox: View {
    var text: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.caption.monospaced())
                .foregroundStyle(Palette.text)
                .textSelection(.enabled)
                .padding(8)
        }
        .frame(maxHeight: 240)
        .background(Palette.codeBackground, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct DiffView: View {
    var diff: EntryDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: diff.isNew ? "doc.badge.plus" : "doc.text")
                    .font(.caption)
                    .foregroundStyle(Palette.secondary)
                Text(diff.path.components(separatedBy: "/").last ?? diff.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                Spacer()
                Text("+\(diff.added)")
                    .font(.caption.monospaced())
                    .foregroundStyle(Palette.added)
                Text("−\(diff.removed)")
                    .font(.caption.monospaced())
                    .foregroundStyle(Palette.removed)
            }
            if let patch = diff.patch {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(patch.components(separatedBy: "\n").prefix(80).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption2.monospaced())
                                .foregroundStyle(line.hasPrefix("+") ? Palette.added
                                    : line.hasPrefix("-") || line.hasPrefix("−") ? Palette.removed
                                    : Palette.secondary)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 260)
                .background(Palette.codeBackground, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

/// The ask/choice card (§7.3): question + 2–12 options + Other… row.
/// Options stay tappable after the 270 s expiry; the host decides.
struct DecisionCard: View {
    var entry: Entry
    var bot: Bot
    @EnvironmentObject private var store: AppStore
    @State private var answeringOption: String?
    @State private var otherText = ""
    @State private var questionExpanded = false
    @State private var shownHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private var data: EntryData { entry.data }
    private var isPending: Bool { data.status == "pending" }
    private var choices: [String] { data.choices ?? [] }
    private var recommended: Int? { data.recommended }

    /// The clamped question hides lines: only then is there something to expand.
    private var clamped: Bool { fullHeight > shownHeight + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Text(data.question ?? "")
                    .font(.headline)
                    .foregroundStyle(Palette.text)
                    .lineLimit(questionExpanded ? nil : 4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
                    .background(alignment: .top) {
                        Text(data.question ?? "").font(.headline).fixedSize(horizontal: false, vertical: true).hidden()
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                    }
                Spacer()
                if questionExpanded || clamped {
                    Button {
                        questionExpanded.toggle()
                    } label: {
                        Image(systemName: questionExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if isPending {
                VStack(spacing: 2) {
                    ForEach(choices.indices, id: \.self) { index in
                        optionRow(index: index)
                    }
                    otherRow
                }
                .padding(.horizontal, -8)
            } else {
                Text(outcomeText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.secondary)
            }
            WorkThreadLine(data: data)
        }
        .padding(16)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Palette.bubbleAgent, in: RoundedRectangle(cornerRadius: 22))
        .padding(.trailing, 40)
    }

    private func optionRow(index: Int) -> some View {
        let choice = choices[index]
        let isRecommended = recommended == index
        let isAnswering = answeringOption == choice
        return Button {
            answer(option: choice)
        } label: {
            HStack(spacing: 10) {
                RowNumber {
                    if isAnswering {
                        Spinner(size: 12)
                    } else {
                        Text("\(index + 1)")
                    }
                }
                Text(choice)
                    .font(isRecommended ? .body.weight(.semibold) : .body)
                    .foregroundStyle(Palette.text)
                Spacer()
                if isRecommended {
                    Text(L("建议"))
                        .font(.caption)
                        .foregroundStyle(Palette.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(answeringOption != nil && !isAnswering ? 0.4 : 1)
        }
        .buttonStyle(RowStyle())
        .disabled(answeringOption != nil)
    }

    private var otherRow: some View {
        HStack(spacing: 10) {
            RowNumber {
                Image(systemName: "pencil")
                    .font(.caption)
            }
            TextField(L("其他…"), text: $otherText)
                .font(.body)
                .onSubmit {
                    answerOther()
                }
            if !otherText.isEmpty {
                Button {
                    answerOther()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Palette.onAccent)
                        .frame(width: 28, height: 28)
                        .background(Palette.accentFill, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minHeight: 44)
    }

    private var outcomeText: String {
        if let selected = data.selected, !selected.isEmpty {
            return selected
        }
        switch data.status {
        case "expired":
            return L("未回答，智能体已继续")
        default:
            return L("已回答")
        }
    }

    private func answer(option: String) {
        guard let api = store.connector.api else { return }
        answeringOption = option
        Task {
            do {
                try await api.respondDecision(entryId: entry.id, option: option)
            } catch {
                answeringOption = nil
            }
        }
    }

    private func answerOther() {
        let text = otherText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let api = store.connector.api else { return }
        otherText = ""
        Task {
            // Other… is sent as a plain message; the host treats it as the answer.
            _ = try? await api.send(botId: entry.botId, text: text, clientNonce: UUID().uuidString)
        }
    }
}

/// The number (or pencil) before a decision option: 24×24, secondary,
/// monospaced digits.
private struct RowNumber<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Palette.secondary)
            .frame(width: 24, height: 24)
            .background(Palette.text.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// An option row lights up while pressed.
private struct RowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Palette.text.opacity(configuration.isPressed ? 0.08 : 0),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// The approval sheet (§7.2): FishPocket chrome (bottom sheet, top radius
/// 36, grabber, close button, {n}/{m} counter) + Codync's three rows.
struct ApprovalSheet: View {
    var entries: [Entry]
    var bot: Bot
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var answeringOptionId: String?
    @State private var detailsExpanded = false

    private var entry: Entry? {
        guard !entries.isEmpty else { return nil }
        return entries[min(index, entries.count - 1)]
    }

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("待审批")) {
                dismiss()
            }
            if let entry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(L("%d / %d", index + 1, entries.count))
                                .font(.subheadline)
                                .foregroundStyle(Palette.secondary)
                            Spacer()
                            if entries.count > 1 {
                                Button(L("下一个")) {
                                    index = (index + 1) % entries.count
                                }
                                .font(.subheadline.weight(.medium))
                            }
                        }
                        PermissionCard(entry: entry, bot: bot)
                            .padding(.trailing, 0)
                    }
                    .padding(.horizontal, 20)
                }
            } else {
                Text(L("没有待审批的请求。"))
                    .font(.body)
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 40)
                Spacer()
            }
        }
        .background(Palette.background)
    }
}
