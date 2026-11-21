import AppIntents
import SwiftUI
import WidgetKit

/// The MiniApps widget: the user's Spaces (small tools), each opening
/// its Space in Discover. Spaces come from the snapshot only; with
/// none the card says so and points at creating one, instead of
/// inventing an example.
struct MiniAppsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot

    static var current: MiniAppsEntry {
        MiniAppsEntry(date: .now, snapshot: WidgetSnapshotStore.read() ?? .empty)
    }
}

struct MiniAppsTimeline: TimelineProvider {
    func placeholder(in context: Context) -> MiniAppsEntry {
        MiniAppsEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (MiniAppsEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : .current)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MiniAppsEntry>) -> Void) {
        completion(Timeline(entries: [.current], policy: .never))
    }
}

struct MiniAppsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "linGyUMiniApps", provider: MiniAppsTimeline()) { entry in
            MiniAppsWidgetView(entry: entry)
                .containerBackground(WidgetPalette.surface, for: .widget)
        }
        .configurationDisplayName("小工具")
        .description("你的小工具，点一下打开。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct MiniAppsWidgetView: View {
    let entry: MiniAppsEntry
    @Environment(\.widgetFamily) private var family

    private var spaces: [WidgetSpaceSnapshot] { entry.snapshot.spaces }

    private var limit: Int {
        switch family {
        case .systemLarge: return 8
        case .systemMedium: return 4
        default: return 2
        }
    }

    var body: some View {
        if !entry.snapshot.paired {
            WidgetEmptyState(text: L("连接一台电脑"))
        } else if spaces.isEmpty {
            WidgetEmptyState(text: L("还没有小工具"), detail: L("描述一个来创建"))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L("小工具")).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 12)).foregroundStyle(WidgetPalette.secondary)
                }
                .foregroundStyle(WidgetPalette.text)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(spaces.prefix(limit), id: \.id) { space in
                        spaceRow(space)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func spaceRow(_ space: WidgetSpaceSnapshot) -> some View {
        Button(intent: OpenBotIntent(WidgetDeepLink.space(space.id))) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 12))
                    .foregroundStyle(WidgetPalette.secondary)
                    .frame(width: 24, height: 24)
                    .background(WidgetPalette.bubble, in: RoundedRectangle(cornerRadius: 7))
                Text(space.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WidgetPalette.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WidgetPalette.tertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("打开小工具"))
        .accessibilityValue(space.title)
    }
}
