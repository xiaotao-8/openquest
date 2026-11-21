import AppIntents
import SwiftUI
import WidgetKit

/// The new-conversation widget: one tap opens a new chat with the lead
/// bot. The lead bot's name comes from the snapshot; with no bots the
/// card says so honestly and still opens the app, which shows the
/// empty roster and the create-a-bot entry.
struct NewConversationEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot

    static var current: NewConversationEntry {
        NewConversationEntry(date: .now, snapshot: WidgetSnapshotStore.read() ?? .empty)
    }

    /// The snapshot writer puts the lead bot first.
    var leadBot: WidgetBotSnapshot? { snapshot.bots.first }
}

struct NewConversationTimeline: TimelineProvider {
    func placeholder(in context: Context) -> NewConversationEntry {
        NewConversationEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (NewConversationEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : .current)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NewConversationEntry>) -> Void) {
        completion(Timeline(entries: [.current], policy: .never))
    }
}

struct NewConversationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "linGyUNewConversation", provider: NewConversationTimeline()) { entry in
            NewConversationWidgetView(entry: entry)
                .containerBackground(WidgetPalette.surface, for: .widget)
        }
        .configurationDisplayName("新建会话")
        .description("和主智能体开始一段新对话。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NewConversationWidgetView: View {
    let entry: NewConversationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if !entry.snapshot.paired {
            WidgetEmptyState(text: L("连接一台电脑"))
        } else {
            Button(intent: OpenBotIntent(WidgetDeepLink.newChat())) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(WidgetPalette.text)
                    Spacer(minLength: 0)
                    Text(L("新建会话"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WidgetPalette.text)
                    if family == .systemMedium {
                        if let lead = entry.leadBot {
                            HStack(spacing: 6) {
                                WidgetAvatar(bot: lead, size: 20)
                                Text(lead.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(WidgetPalette.secondary)
                                    .lineLimit(1)
                            }
                        } else {
                            Text(L("还没有智能体"))
                                .font(.system(size: 12))
                                .foregroundStyle(WidgetPalette.secondary)
                        }
                    } else if let lead = entry.leadBot {
                        Text(lead.name)
                            .font(.system(size: 12))
                            .foregroundStyle(WidgetPalette.secondary)
                            .lineLimit(1)
                    } else {
                        Text(L("还没有智能体"))
                            .font(.system(size: 12))
                            .foregroundStyle(WidgetPalette.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("新建会话"))
            .accessibilityHint(L("和主智能体开始一段新对话"))
        }
    }
}
