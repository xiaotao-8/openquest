import SwiftUI
import WidgetKit

/// Writes the roster + Spaces snapshot the widgets read, into the
/// shared App Group (`group.cn.lingyu`), then asks WidgetKit to redraw.
///
/// Call it whenever the roster or the Spaces list changes (see
/// `appstore-additions.swift` for the call points). The snapshot holds
/// display data only — no pairing keys, no host state — so the widget
/// extension can render without ever talking to the host.
///
/// The lead bot goes first in the snapshot, so the new-conversation
/// widget can show it without knowing the roster order.
@MainActor
final class WidgetSnapshotWriter {
    static let shared = WidgetSnapshotWriter()

    private init() {}

    func write(bots: [Bot], spaces: [SpaceItem], paired: Bool) {
        let ordered = bots.filter { !$0.hidden }.sorted {
            ($0.lead ? 0 : 1) < ($1.lead ? 0 : 1)
        }
        let snapshot = WidgetSnapshot(
            paired: paired,
            language: L10n.language,
            bots: ordered.map { bot in
                WidgetBotSnapshot(
                    id: bot.id,
                    name: bot.name,
                    unread: bot.unread,
                    waiting: bot.waiting,
                    working: bot.isBusyOutside,
                    needsYou: bot.needsYouOutside,
                    avatarColor: bot.avatarColor,
                    avatarShape: bot.avatarShape)
            },
            spaces: spaces.map { WidgetSpaceSnapshot(id: $0.id.uuidString, title: $0.title) },
            updatedAt: Date())
        WidgetSnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
