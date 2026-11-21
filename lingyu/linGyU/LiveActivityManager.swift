import ActivityKit
import Foundation

/// Starts, updates and ends this phone's Live Activities, from the app
/// process. The widget extension only renders them; it never starts one.
///
/// Two kinds:
/// - Call: a voice call with a bot (bot, elapsed time, current step,
///   mute/end buttons that hand the app a deep link).
/// - Approval: one pending approval (bot, request title, "查看" button
///   that opens the approvals page). The decision is always made in the
///   app; the activity ends when the entry is answered or withdrawn.
///
/// Nothing here touches the host or pairing keys. Activities only run
/// when iOS allows them (`areActivitiesEnabled`); a denied toggle means
/// `request` is skipped silently and the in-app cards stay the only
/// surface. The app's `Info.plist` must carry
/// `NSSupportsLiveActivities` (see `project-additions.yml`), or every
/// request throws.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    /// Live call activities, keyed by bot id.
    private var callActivities: [String: Activity<CodyncCallAttributes>] = [:]
    /// Live approval activities, keyed by entry id.
    private var approvalActivities: [String: Activity<CodyncApprovalAttributes>] = [:]

    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private init() {
        // Adopt activities that outlived the last launch (for example a
        // call that kept running while the app was killed).
        for activity in Activity<CodyncCallAttributes>.activities {
            callActivities[activity.attributes.botId] = activity
        }
        for activity in Activity<CodyncApprovalAttributes>.activities {
            approvalActivities[activity.attributes.entryId] = activity
        }
    }

    // MARK: - Call

    /// Start the call activity for a bot. No-op when one is already
    /// running for that bot, or when iOS has Live Activities off.
    func startCall(botId: String, name: String, avatarShape: String, avatarColor: String,
                   step: String, status: String = "working") {
        guard areActivitiesEnabled, callActivities[botId] == nil else { return }
        let attributes = CodyncCallAttributes(botId: botId, name: name, avatarShape: avatarShape,
                                              avatarColor: avatarColor,
                                              link: WidgetDeepLink.call(botId))
        let state = CodyncCallAttributes.ContentState(step: step, status: status,
                                                      startedAt: Date(), muted: false)
        do {
            callActivities[botId] = try Activity.request(attributes: attributes, contentState: state)
        } catch {
            // Live Activities off, or the system refused: the in-app call
            // view stays the only surface. Never crash the call for this.
        }
    }

    /// Update the call's step, status or mute state.
    func updateCall(botId: String, step: String, status: String, muted: Bool) async {
        guard let activity = callActivities[botId] else { return }
        let state = CodyncCallAttributes.ContentState(step: step, status: status,
                                                      startedAt: activity.contentState.startedAt,
                                                      muted: muted)
        await activity.update(using: state)
    }

    /// End the call activity when the call ends.
    func endCall(botId: String) async {
        guard let activity = callActivities.removeValue(forKey: botId) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    // MARK: - Approval

    /// Start the approval activity for one pending entry. No-op when
    /// one is already running for that entry, or when iOS has Live
    /// Activities off. At most one activity per entry: a second pending
    /// entry from the same bot starts its own activity.
    func startApproval(entryId: String, botId: String, botName: String, title: String, detail: String = "") {
        guard areActivitiesEnabled, approvalActivities[entryId] == nil else { return }
        let attributes = CodyncApprovalAttributes(entryId: entryId, botId: botId, botName: botName, title: title)
        let state = CodyncApprovalAttributes.ContentState(detail: detail, startedAt: Date())
        do {
            approvalActivities[entryId] = try Activity.request(attributes: attributes, contentState: state)
        } catch {
            // Same as calls: the in-app approval card stays the surface.
        }
    }

    /// End the approval activity when its entry is answered, denied,
    /// or withdrawn. Called from `answerApproval` and from the entry's
    /// removal path (see `appstore-additions.swift`).
    func endApproval(entryId: String) async {
        guard let activity = approvalActivities.removeValue(forKey: entryId) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    /// End every approval activity (for example on sign-out / start-over).
    func endAllApprovals() async {
        let activities = approvalActivities
        approvalActivities = [:]
        for (_, activity) in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
