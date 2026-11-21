import ActivityKit
import SwiftUI
import WidgetKit

/// The status words a Live Activity shows, from the same status strings
/// the app's activity presentation uses. Only "needs you" and errors
/// stand out; everything else stays quiet.
enum WidgetActivityStatus {
    static func title(for status: String) -> String {
        switch status {
        case "sending": return L("发送中")
        case "queued", "waiting": return L("等待电脑")
        case "working": return L("进行中")
        case "needsInput": return L("需要你确认")
        case "idle", "completed": return L("已完成")
        case "error": return L("失败")
        case "onCall": return L("通话中")
        default: return L("等待电脑")
        }
    }

    static func tint(for status: String) -> Color {
        switch status {
        case "needsInput": return WidgetPalette.attention
        case "error": return WidgetPalette.danger
        case "idle", "completed": return WidgetPalette.added
        default: return WidgetPalette.text
        }
    }
}

// MARK: - Call Live Activity

/// A voice call with a bot: the bot, the call's length, the current
/// step, and mute / end buttons. The buttons run intents in the app
/// (see `CallControlIntents`); the extension never touches the call.
struct LinGyUCallActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LinGyUCallAttributes.self) { context in
            callCard(context: context)
                .activityBackgroundTint(WidgetPalette.surface)
                .activitySystemActionForegroundColor(WidgetPalette.text)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 12) {
                        WidgetAvatar(name: context.attributes.name, color: context.attributes.avatarColor,
                                     shape: context.attributes.avatarShape, size: 44)
                        callTitle(context: context)
                    }
                    .frame(maxHeight: .infinity)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    callButtons(context: context, fill: Color.white.opacity(0.18))
                        .frame(maxHeight: .infinity)
                }
            } compactLeading: {
                WidgetAvatar(name: context.attributes.name, color: context.attributes.avatarColor,
                             shape: context.attributes.avatarShape, size: 20)
            } compactTrailing: {
                Text(context.state.startedAt, style: .timer)
                    .font(.system(size: 14).monospacedDigit())
                    .foregroundStyle(WidgetPalette.secondary)
                    .frame(maxWidth: 44)
            } minimal: {
                WidgetAvatar(name: context.attributes.name, color: context.attributes.avatarColor,
                             shape: context.attributes.avatarShape, size: 20)
                    .accessibilityLabel("\(context.attributes.name), \(L("通话中"))")
            }
            .keylineTint(WidgetActivityStatus.tint(for: context.state.status))
            .widgetURL(context.attributes.link)
        }
    }

    private func callTitle(context: ActivityViewContext<LinGyUCallAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(context.state.startedAt, style: .timer)
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(WidgetPalette.secondary)
            Text(context.attributes.name)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(WidgetPalette.text)
                .lineLimit(1)
        }
    }

    private func callButtons(context: ActivityViewContext<LinGyUCallAttributes>, fill: Color) -> some View {
        HStack(spacing: 10) {
            Button(intent: MuteCallIntent(botId: context.attributes.botId)) {
                Image(systemName: context.state.muted ? "mic.slash" : "mic")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(context.state.muted ? WidgetPalette.onAccent : WidgetPalette.text)
                    .frame(width: 44, height: 44)
                    .background(context.state.muted ? WidgetPalette.text : fill, in: Circle())
            }
            .accessibilityLabel(context.state.muted ? L("取消静音") : L("静音"))
            Button(intent: EndCallIntent(botId: context.attributes.botId)) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(WidgetPalette.danger, in: Circle())
            }
            .accessibilityLabel(L("挂断"))
        }
        .buttonStyle(.plain)
    }

    private func callCard(context: ActivityViewContext<LinGyUCallAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                WidgetAvatar(name: context.attributes.name, color: context.attributes.avatarColor,
                             shape: context.attributes.avatarShape, size: 44)
                callTitle(context: context)
                Spacer(minLength: 8)
                callButtons(context: context, fill: WidgetPalette.text.opacity(0.12))
            }
            Text(context.state.step.isEmpty ? WidgetActivityStatus.title(for: context.state.status) : context.state.step)
                .font(.system(size: 13))
                .foregroundStyle(WidgetPalette.secondary)
                .lineLimit(2)
        }
        .padding(16)
    }
}

// MARK: - Approval Live Activity

/// A pending approval: the bot, the request's title, and a "查看" button
/// that opens the approvals page in the app. The decision is always
/// made in the app; the island never approves or denies by itself
/// (that would need the pairing key in the shared container).
struct LinGyUApprovalActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LinGyUApprovalAttributes.self) { context in
            approvalCard(context: context)
                .activityBackgroundTint(WidgetPalette.surface)
                .activitySystemActionForegroundColor(WidgetPalette.text)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    approvalMark
                        .frame(maxHeight: .infinity)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 3) {
                        Text(context.attributes.botName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WidgetPalette.text)
                        Text(context.attributes.title)
                            .font(.system(size: 13))
                            .foregroundStyle(WidgetPalette.secondary)
                    }
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startedAt, style: .timer)
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(WidgetPalette.tertiary)
                        .frame(maxHeight: .infinity)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    reviewButton(entryId: context.attributes.entryId)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                approvalMark
            } compactTrailing: {
                Circle().fill(WidgetPalette.attention).frame(width: 8, height: 8)
            } minimal: {
                approvalMark
                    .accessibilityLabel("\(context.attributes.botName), \(L("需要你确认"))")
            }
            .keylineTint(WidgetPalette.attention)
            .widgetURL(WidgetDeepLink.approvals(context.attributes.entryId))
        }
    }

    private var approvalMark: some View {
        Image(systemName: "hand.raised.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(WidgetPalette.attention)
            .frame(width: 28, height: 28)
    }

    private func reviewButton(entryId: String) -> some View {
        Button(intent: OpenApprovalIntent(entryId: entryId)) {
            Label(L("查看"), systemImage: "hand.raised.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WidgetPalette.onAccent)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(WidgetPalette.attention, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func approvalCard(context: ActivityViewContext<LinGyUApprovalAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                approvalMark
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.botName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WidgetPalette.text)
                        .lineLimit(1)
                    Text(context.attributes.title)
                        .font(.system(size: 13))
                        .foregroundStyle(WidgetPalette.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(context.state.startedAt, style: .timer)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(WidgetPalette.tertiary)
            }
            if !context.state.detail.isEmpty {
                Text(context.state.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(3)
            }
            reviewButton(entryId: context.attributes.entryId)
        }
        .padding(16)
    }
}
