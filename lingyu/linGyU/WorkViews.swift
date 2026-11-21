import SwiftUI

// MARK: - Work task helpers

extension WorkTask {
    /// What the task is doing, as a short line.
    func what() -> String {
        if status == "needsYou" { return L("需要你确认") }
        return activity.isEmpty ? title : activity
    }

    /// The task's line in a timeline: what it is doing, waiting for, or how it ended.
    func line() -> String {
        switch status {
        case "needsYou": return L("需要你确认")
        case "working": return activity.isEmpty ? L("正在干活") : activity
        case "waiting": return waitLine()
        case "done": return result ?? L("已完成")
        case "failed": return result ?? L("失败")
        case "stopped": return L("已停止")
        default: return title
        }
    }

    private func waitLine() -> String {
        guard let wait else { return L("正在等待") }
        switch wait.kind {
        case "cutIn": return L("刚被插队，即将重新开始")
        case "behind": return wait.ahead > 0 ? L("前面还有 %d 个", wait.ahead) : L("下一个就是它")
        case "next": return L("下一个就是它")
        case "after": return L("排在当前任务之后")
        case "usage": return L("接近用量上限：一次只做一个")
        default: return L("正在等待")
        }
    }

    var word: String {
        switch status {
        case "waiting": return L("等待中")
        case "working": return L("进行中")
        case "needsYou": return L("需要你确认")
        case "done": return L("已完成")
        case "failed": return L("失败")
        case "stopped": return L("已停止")
        default: return status
        }
    }

    var hasEnded: Bool { status == "done" || status == "failed" || status == "stopped" }

    /// How long the task ran, in seconds (0 while it runs).
    var timeTaken: TimeInterval {
        guard let startedAt, let endedAt else { return 0 }
        return max(0, TimeInterval(endedAt - startedAt) / 1000)
    }

    /// It gives way to the next task: live, and nobody asked for it.
    var givesWay: Bool { isLive && source == nil }

    /// A waiting task can cut in when it is not already first.
    var canCutIn: Bool { status == "waiting" && wait?.kind != "next" }

    var canRetry: Bool { (status == "failed" || status == "stopped") && source?.kind != "request" }
}

// MARK: - Work sections

/// A bot's work, split the way the roster and the timeline show it.
struct WorkSections {
    var needsYou: [WorkTask] = []
    var working: [WorkTask] = []
    var waiting: [WorkTask] = []
    var recent: [WorkTask] = []

    init(tasks: [WorkTask]) {
        needsYou = tasks.filter { $0.status == "needsYou" }
        working = tasks.filter { $0.status == "working" }
        waiting = tasks.filter { $0.status == "waiting" }
        recent = tasks.filter { $0.hasEnded }
    }

    var live: [WorkTask] { needsYou + working }
    var isIdle: Bool { live.isEmpty && waiting.isEmpty }
    /// Exactly one working task and nothing else.
    var solo: WorkTask? { working.count == 1 && needsYou.isEmpty && waiting.isEmpty ? working[0] : nil }
    /// Exactly one live task: the capsule can stop it directly.
    var stoppable: WorkTask? { live.count == 1 ? live[0] : nil }
    func free(maxThreads: Int?) -> Int { max(0, (maxThreads ?? 3) - live.count) }
    func threadsCount(maxThreads: Int?) -> String { "\(live.count) / \(maxThreads ?? 3)" }

    /// "2 working · 1 waiting", only the non-zero parts.
    func counts() -> String {
        var parts: [String] = []
        if !working.isEmpty { parts.append(L("%d 个在干活", working.count)) }
        if !waiting.isEmpty { parts.append(L("%d 个在等待", waiting.count)) }
        return parts.joined(separator: " · ")
    }

    func capsuleLabel() -> String {
        let parts: [String]
        if !needsYou.isEmpty {
            parts = [L("需要你确认"), counts()].filter { !$0.isEmpty }
        } else {
            parts = [solo?.what() ?? counts()].filter { !$0.isEmpty }
        }
        return L("工作") + " · " + parts.joined(separator: " · ")
    }

    /// The actions a task offers in its row and context menu.
    func actions(for task: WorkTask) -> [WorkAction] {
        switch task.status {
        case "working", "needsYou": return [.stop]
        case "waiting":
            if task == waiting.first { return task.canCutIn ? [.cutIn, .drop] : [.drop] }
            return [.first, .drop]
        case "failed", "stopped": return task.canRetry ? [.retry, .drop] : [.drop]
        case "done": return [.drop]
        default: return []
        }
    }
}

enum WorkAction: String, CaseIterable {
    case stop, cutIn, first, drop, retry

    var title: String {
        switch self {
        case .stop: return L("停止")
        case .cutIn: return L("插队")
        case .first: return L("移到最前")
        case .drop: return L("丢弃")
        case .retry: return L("重试")
        }
    }

    var symbol: String {
        switch self {
        case .stop: return "stop.fill"
        case .cutIn: return "arrow.turn.right.up"
        case .first: return "arrow.up.to.line"
        case .drop: return "xmark"
        case .retry: return "arrow.clockwise"
        }
    }

    var destructive: Bool { self == .stop || self == .drop }
}

// MARK: - Bot roster lines

extension Bot {
    /// What the roster shows when the bot needs you: its activity, or a
    /// plain "Needs approval".
    var needsYouLine: String {
        needsInput ? (activity.isEmpty ? L("需要审批") : activity) : L("需要你确认")
    }

    enum RosterLine { case needsYou, activity, lastMessage, work }

    var rosterLine: RosterLine {
        if needsInput || work.contains(where: { $0.status == "needsYou" }) { return .needsYou }
        if isWorking { return .activity }
        if work.isEmpty { return .lastMessage }
        return .work
    }

    /// The line under the bot's name outside its chat.
    var outsideLine: String {
        if needsYouOutside {
            if work.contains(where: { $0.status == "needsYou" }) { return L("需要你确认") }
            return activity
        }
        if isWorking { return activity }
        let sections = WorkSections(tasks: work)
        if !sections.isIdle { return sections.counts() }
        return ""
    }

    var workSections: WorkSections { WorkSections(tasks: work) }
}

// MARK: - Work mark

/// The mark before a task in a timeline: an orb while it works, a stroked
/// circle while it waits, a filled dot when it failed.
struct WorkMark: View {
    var task: WorkTask
    var size: CGFloat = 14

    var body: some View {
        switch task.status {
        case "needsYou":
            ThinkingOrb(state: .listening, size: size, color: Palette.warning)
        case "working":
            ThinkingOrb(state: .working, size: size, color: Palette.secondary)
        case "waiting", "done":
            Circle()
                .stroke(task.status == "waiting" ? Palette.tertiary : Palette.secondary, lineWidth: 1.5)
                .frame(width: 10, height: 10)
        case "failed", "stopped":
            Circle()
                .fill(Palette.danger)
                .frame(width: 8, height: 8)
        default:
            Circle()
                .stroke(Palette.tertiary, lineWidth: 1.5)
                .frame(width: 10, height: 10)
        }
    }
}

/// A live timer from `startedAt` (ms), or the elapsed mm:ss once ended.
struct WorkElapsed: View {
    var task: WorkTask

    var body: some View {
        if task.hasEnded {
            Text(Self.mmss(task.timeTaken))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Palette.tertiary)
        } else if let startedAt = task.startedAt {
            Text(Date(timeIntervalSince1970: TimeInterval(startedAt) / 1000), style: .timer)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Palette.tertiary)
        }
    }

    static func mmss(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Work capsule

/// The floating capsule above the composer while the bot works: what it is
/// doing, a timer, and a stop button when it can be stopped. Tapping it
/// opens the details.
struct WorkCapsule: View {
    var bot: Bot
    var onStop: (() -> Void)?
    var onTap: () -> Void

    var body: some View {
        let sections = bot.workSections
        let stoppable = sections.stoppable
        let markTask = sections.live.first ?? sections.waiting.first
        HStack(spacing: 4) {
            Button(action: onTap) {
                HStack(spacing: 8) {
                    if let markTask {
                        WorkMark(task: markTask)
                    }
                    Text(sections.capsuleLabel())
                        .font(.subheadline)
                        .foregroundStyle(Palette.text)
                    if let startedAt = sections.live.first?.startedAt {
                        Text(Date(timeIntervalSince1970: TimeInterval(startedAt) / 1000), style: .timer)
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(Palette.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            if stoppable != nil, let onStop {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.accentFill)
                        .frame(width: 34, height: 34)
                        .background(Palette.bubbleUser, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .padding(.leading, 14)
        .padding(.trailing, stoppable != nil ? 2 : 14)
        .glass(in: Capsule())
        .padding(.horizontal, 16)
    }
}

// MARK: - Work timeline

/// A bot's work as a timeline: live rows, then the waiting queue, then
/// what finished. `onAction` runs the tapped action (the caller talks to
/// the host); `onOpen` opens the task's thread when it has one.
struct WorkTimeline: View {
    enum Mode { case plain, full }

    var bot: Bot
    var mode: Mode = .full
    var outlined: Bool = false
    var onAction: (WorkTask, WorkAction) -> Void = { _, _ in }
    var onOpen: (WorkTask) -> Void = { _ in }

    var body: some View {
        let sections = bot.workSections
        switch mode {
        case .plain:
            CardSection(outlined: outlined) {
                let rows = sections.live.map { ($0, nil as Int?) } + sections.waiting.enumerated().map { ($0.element, $0.offset + 1) }
                ForEach(Array(rows.enumerated()), id: \.element.0.id) { index, pair in
                    if index > 0 { Hairline() }
                    WorkRow(bot: bot, task: pair.0, number: pair.1, actions: sections.actions(for: pair.0), onAction: onAction, onOpen: onOpen)
                }
            }
        case .full:
            VStack(alignment: .leading, spacing: 32) {
                CardSection(title: L("线程"), accessory: AnyView(
                    Text(sections.threadsCount(maxThreads: bot.maxThreads))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                )) {
                    let live = sections.live
                    ForEach(Array(live.enumerated()), id: \.element.id) { index, task in
                        if index > 0 { Hairline() }
                        WorkRow(bot: bot, task: task, number: nil, actions: sections.actions(for: task), onAction: onAction, onOpen: onOpen)
                    }
                    if !live.isEmpty, sections.free(maxThreads: bot.maxThreads) > 0 { Hairline() }
                    ForEach(0..<sections.free(maxThreads: bot.maxThreads), id: \.self) { index in
                        if index > 0 { Hairline() }
                        FreeRow()
                    }
                }
                if !sections.waiting.isEmpty {
                    CardSection(title: L("事件箱")) {
                        ForEach(Array(sections.waiting.enumerated()), id: \.element.id) { index, task in
                            if index > 0 { Hairline() }
                            WorkRow(bot: bot, task: task, number: index + 1, actions: sections.actions(for: task), onAction: onAction, onOpen: onOpen)
                        }
                    }
                }
                if !sections.recent.isEmpty {
                    CardSection(title: L("最近")) {
                        ForEach(Array(sections.recent.enumerated()), id: \.element.id) { index, task in
                            if index > 0 { Hairline() }
                            WorkRow(bot: bot, task: task, number: nil, actions: sections.actions(for: task), onAction: onAction, onOpen: onOpen)
                        }
                    }
                }
            }
        }
    }
}

private struct FreeRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .stroke(Palette.tertiary, lineWidth: 1.5)
                .frame(width: 10, height: 10)
            Text(L("空闲"))
                .foregroundStyle(Palette.tertiary)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct WorkRow: View {
    var bot: Bot
    var task: WorkTask
    var number: Int?
    var actions: [WorkAction]
    var onAction: (WorkTask, WorkAction) -> Void
    var onOpen: (WorkTask) -> Void

    var body: some View {
        let openable = task.thread != nil && task.hasEnded
        HStack(spacing: 12) {
            if let number {
                Text("\(number)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 24, height: 24)
                    .background(Palette.text.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                WorkMark(task: task)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    if let source = task.source, source.kind == "routine" {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption2)
                            .foregroundStyle(Palette.secondary)
                    }
                }
                HStack(spacing: 6) {
                    Text(task.line())
                        .font(.caption)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                    if let folder = task.folder, !folder.isEmpty {
                        Text("· \(folder.components(separatedBy: "/").last ?? folder)")
                            .font(.caption)
                            .foregroundStyle(Palette.tertiary)
                            .lineLimit(1)
                    }
                    WorkElapsed(task: task)
                }
            }
            Spacer(minLength: 12)
            if let primary = actions.first {
                if primary == .cutIn {
                    Button { onAction(task, .cutIn) } label: {
                        Text(L("插队"))
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Palette.bubbleUser, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { onAction(task, primary) } label: {
                        Image(systemName: primary.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(primary.destructive ? Palette.danger : Palette.secondary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, -6)
                    .padding(.trailing, -8)
                }
            }
            if openable {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture { if openable { onOpen(task) } }
        .contextActions {
            actions.dropFirst().map { action in
                MenuItem(action.title, icon: action.symbol, destructive: action.destructive) {
                    onAction(task, action)
                }
            }
        }
    }
}

// MARK: - Stop work dialog

extension View {
    /// "Stop this task?" — what it already changed stays.
    func stopWorkDialog(isPresented: Binding<Bool>, onStop: @escaping () -> Void) -> some View {
        codyncDialog(isPresented: isPresented, title: L("停止这个任务？"), message: L("已经改动的东西会保留。"), actions: [
            CodyncDialogAction(title: L("停止"), isDestructive: true, action: onStop),
            CodyncDialogAction(title: L("取消"), action: {}),
        ])
    }
}
