import ActivityKit
import Foundation

/// The two Live Activities. Both are driven from the app by
/// `LiveActivityManager`; the extension only renders them. Neither
/// carries pairing keys or host state: the call activity carries the
/// bot's display data and its current step, the approval activity
/// carries the pending entry's title. Answering always happens in the
/// app (see `OpenApprovalIntent`).

/// A voice call with a bot: the bot, how long the call has run, and
/// the current step. `link` opens the call view in the app.
struct CodyncCallAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        /// The call's current step, or "" to show the state title.
        var step: String
        /// "working" / "needsInput" / "idle" / "error" (same words the
        /// app's activity presentation uses).
        var status: String
        var startedAt: Date
        var muted: Bool
    }

    var botId: String
    var name: String
    var avatarShape: String
    var avatarColor: String
    var link: URL?
}

/// A pending approval: the entry's title and which bot asked. Tapping
/// "查看" opens the approvals page in the app; the activity ends when
/// the entry is answered or withdrawn.
struct CodyncApprovalAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        /// One line of detail under the title, or "" for title only.
        var detail: String
        var startedAt: Date
    }

    var entryId: String
    var botId: String
    var botName: String
    var title: String
}
