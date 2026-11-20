import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - 锁屏审批：审批卡出现时锁屏上浮一个 LiveActivity，点允许/拒绝
// 走 openquest://approval deep link 回 App 作答（主 App 的 onOpenURL 接）。
// 手表端另有手表 App，用户目前没有手表，先做锁屏。

@main
struct ApprovalWidgetBundle: WidgetBundle {
    var body: some Widget {
        ApprovalLiveActivity()
    }
}

struct ApprovalLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ApprovalAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text("需要批准")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
                Text(context.attributes.action)
                    .font(.subheadline)
                    .lineLimit(2)
                if !context.attributes.impact.isEmpty {
                    Text(context.attributes.impact)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 10) {
                    Link("拒绝", destination: Self.url(
                        convId: context.attributes.convId, choice: "deny"))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(Color.white.opacity(0.12), in: Capsule())
                    Link("允许", destination: Self.url(
                        convId: context.attributes.convId, choice: "allow"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(Color.green, in: Capsule())
                }
            }
            .padding(12)
            .activityBackgroundTint(Color.black)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("需要批准").font(.caption2.weight(.bold)).foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.action).font(.caption2).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        Link("拒绝", destination: Self.url(
                            convId: context.attributes.convId, choice: "deny"))
                        Link("允许", destination: Self.url(
                            convId: context.attributes.convId, choice: "allow"))
                    }
                    .font(.subheadline.weight(.semibold))
                }
            } compactLeading: {
                Image(systemName: "exclamationmark.shield")
            } compactTrailing: {
                Image(systemName: "checkmark.shield")
            } minimal: {
                Image(systemName: "exclamationmark.shield")
            }
        }
    }

    private static func url(convId: String, choice: String) -> URL {
        URL(string: "openquest://approval?conv=\(convId)&choice=\(choice)")!
    }
}
