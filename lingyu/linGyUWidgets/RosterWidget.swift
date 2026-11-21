import AppIntents
import SwiftUI
import WidgetKit

/// The roster widget: which bots need the user, which are working, and
/// their unread counts. The app writes the roster snapshot and reloads
/// this widget when a bot's state changes; the timeline itself never
/// polls, so what it shows is always the app's last report.
///
/// No fake data: the gallery placeholder is the empty snapshot, and a
/// widget with no snapshot shows the unpaired empty state.
struct RosterEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot

    static var current: RosterEntry {
        RosterEntry(date: .now, snapshot: WidgetSnapshotStore.read() ?? .empty)
    }
}

struct RosterTimeline: TimelineProvider {
    func placeholder(in context: Context) -> RosterEntry {
        RosterEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (RosterEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : .current)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RosterEntry>) -> Void) {
        completion(Timeline(entries: [.current], policy: .never))
    }
}

struct RosterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "linGyURoster", provider: RosterTimeline()) { entry in
            RosterWidgetView(entry: entry)
                .containerBackground(WidgetPalette.surface, for: .widget)
        }
        .configurationDisplayName("智能体")
        .description("哪些智能体需要你、哪些还在干活。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct RosterWidgetView: View {
    let entry: RosterEntry
    @Environment(\.widgetFamily) private var family

    private var bots: [WidgetBotSnapshot] { entry.snapshot.bots }
    private var needs: Int { bots.filter(\.needsYou).count }
    private var working: Int { bots.filter { $0.working && !$0.needsYou }.count }
    private var count: Int { needs > 0 ? needs : working > 0 ? working : bots.count }
    private var label: String {
        needs > 0 ? L("需要你确认") : working > 0 ? L("进行中") : bots.isEmpty ? L("还没有智能体") : L("一切正常")
    }

    /// Needs the user first, then working, then the snapshot order
    /// (the writer puts the lead bot first; the sort is stable).
    private var ordered: [WidgetBotSnapshot] {
        bots.sorted {
            let rank: (WidgetBotSnapshot) -> Int = { $0.needsYou ? 0 : $0.working ? 1 : 2 }
            return rank($0) < rank($1)
        }
    }

    private var mostUrgent: WidgetBotSnapshot? { ordered.first }

    var body: some View {
        if !entry.snapshot.paired {
            switch family {
            case .accessoryInline:
                Label(L("连接一台电脑"), systemImage: "desktopcomputer")
            case .accessoryCircular:
                Image(systemName: "desktopcomputer")
                    .accessibilityLabel(L("连接一台电脑"))
            case .accessoryRectangular:
                Label(L("连接一台电脑"), systemImage: "desktopcomputer")
                    .font(.caption)
            default:
                WidgetEmptyState(text: L("连接一台电脑"))
            }
        } else {
            switch family {
            case .accessoryInline:
                Text(headline).widgetURL(mostUrgent.map { WidgetDeepLink.bot($0.id) })
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Text("\(count)")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text(needs > 0 ? L("需要你确认") : working > 0 ? L("进行中") : L("个智能体"))
                        .font(.system(size: 9))
                }
                .widgetURL(mostUrgent.map { WidgetDeepLink.bot($0.id) })
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    ForEach(ordered.prefix(2), id: \.id) { bot in
                        Text("\(bot.name) · \(widgetStateLabel(needsYou: bot.needsYou, working: bot.working).label)")
                            .font(.system(size: 10)).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .widgetURL(mostUrgent.map { WidgetDeepLink.bot($0.id) })
            case .systemLarge:
                VStack(alignment: .leading, spacing: 10) {
                    header
                    HStack {
                        summary
                        Spacer()
                        Text(L("%d 个智能体", bots.count))
                            .font(.system(size: 11)).foregroundStyle(WidgetPalette.secondary)
                    }
                    Divider()
                    botRows(limit: 6)
                    Spacer(minLength: 0)
                }
            case .systemMedium:
                HStack(alignment: .center, spacing: 16) {
                    summary.frame(width: 76, alignment: .leading)
                    Rectangle().fill(WidgetPalette.border).frame(width: 1)
                    botRows(limit: 3)
                }
            default:
                VStack(alignment: .leading, spacing: 10) {
                    header
                    Spacer(minLength: 0)
                    summary
                    HStack(spacing: -4) {
                        ForEach(ordered.prefix(3), id: \.id) { bot in
                            WidgetAvatar(bot: bot, size: 23)
                        }
                        Spacer(minLength: 0)
                        if working > 0 && needs > 0 {
                            Text(L("%d 个在干活", working))
                                .font(.system(size: 9)).foregroundStyle(WidgetPalette.secondary)
                        }
                    }
                }
                .widgetURL(mostUrgent.map { WidgetDeepLink.bot($0.id) })
            }
        }
    }

    private var headline: String {
        if bots.isEmpty { return L("还没有智能体") }
        if needs > 0 { return L("%d 个请求等你确认", needs) }
        if working > 0 { return L("%d 个在干活", working) }
        return L("%d 个智能体", bots.count)
    }

    private var header: some View {
        HStack {
            Text(L("智能体")).font(.system(size: 13, weight: .semibold))
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 12)).foregroundStyle(WidgetPalette.secondary)
        }
        .foregroundStyle(WidgetPalette.text)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(count)")
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(needs > 0 ? WidgetPalette.attention : WidgetPalette.text)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WidgetPalette.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func botRows(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ordered.prefix(limit), id: \.id) { bot in
                botRow(bot)
            }
            if bots.isEmpty {
                Text(L("在 Codync 里新建第一个智能体。"))
                    .font(.system(size: 12)).foregroundStyle(WidgetPalette.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Each row is a button running `OpenBotIntent` in the app, so the
    /// tap opens that bot's chat (a plain URL intent does not launch
    /// the app for a custom scheme).
    private func botRow(_ bot: WidgetBotSnapshot) -> some View {
        let state = widgetStateLabel(needsYou: bot.needsYou, working: bot.working)
        return Button(intent: OpenBotIntent(WidgetDeepLink.bot(bot.id))) {
            HStack(spacing: 7) {
                WidgetAvatar(bot: bot, size: 24)
                Text(bot.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WidgetPalette.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                WidgetUnreadBadge(count: bot.unread, waiting: bot.waiting > 0)
                Text(state.label)
                    .font(.system(size: 10, weight: bot.needsYou ? .semibold : .regular))
                    .foregroundStyle(state.tint)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
