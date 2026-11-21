import Foundation

/// The snapshot the app writes for its widgets, and the widgets read.
///
/// The widget extension runs in its own process: it never talks to the
/// host and never sees pairing keys. Everything it shows comes from this
/// snapshot, written into the shared App Group
/// (`group.cn.lingyu`) by `WidgetSnapshotWriter` in the app whenever the
/// roster or the Spaces list changes.
///
/// This file is compiled into both targets (the app target lists it
/// explicitly, like the original lists its intents in both targets), so
/// it must not import anything the app owns: Foundation only.
struct WidgetBotSnapshot: Codable, Sendable, Equatable {
    var id: String
    var name: String
    var unread: Int
    var waiting: Int
    var working: Bool
    /// Needs the user (amber state), as opposed to merely working.
    var needsYou: Bool
    var avatarColor: String
    var avatarShape: String
}

struct WidgetSpaceSnapshot: Codable, Sendable, Equatable {
    var id: String
    var title: String
}

/// The whole widget snapshot: one JSON blob in the shared App Group.
/// `paired` tells the widget whether "no bots" means "nothing created
/// yet" (paired) or "no computer connected" (not paired), so the empty
/// state stays honest instead of guessing.
struct WidgetSnapshot: Codable, Sendable, Equatable {
    var paired: Bool
    /// The app's interface language ("zh" / "en"), mirrored here so the
    /// extension can localise without its own settings store.
    var language: String
    var bots: [WidgetBotSnapshot]
    var spaces: [WidgetSpaceSnapshot]
    var updatedAt: Date

    static let empty = WidgetSnapshot(paired: false, language: "zh", bots: [], spaces: [],
                                      updatedAt: Date(timeIntervalSince1970: 0))
}

enum WidgetSnapshotStore {
    static let suiteName = "group.cn.lingyu"
    static let snapshotKey = "cn.lingyu.widgetSnapshot"
    static let languageKey = "cn.lingyu.language"

    /// The last snapshot the app wrote, or nil when nothing was ever
    /// written (or the App Group is unavailable under this signing).
    static func read() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// False when the shared App Group is unavailable (for example a
    /// free personal signing that did not provision the group): the
    /// caller keeps the old snapshot and the widgets show their
    /// unpaired empty state.
    @discardableResult
    static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: snapshotKey)
        defaults.set(snapshot.language, forKey: languageKey)
        return true
    }
}
