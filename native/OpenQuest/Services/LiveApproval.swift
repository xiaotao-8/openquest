import ActivityKit
import Foundation

// MARK: - 锁屏审批（LiveActivity）
// 审批卡出现时在锁屏上起一个活动，点允许/拒绝走 openquest://approval
// deep link 回 App 作答。不用 App Groups（免费个人签名不可用），
// 审批内容随 Activity 本身携带；起不来也不影响卡片本身。

enum LiveApproval {
    @MainActor
    static func start(convId: UUID, action: String, impact: String, risk: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // 同一时间只留一个审批活动，旧的先收掉。
        for a in Activity<ApprovalAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
        let attrs = ApprovalAttributes(
            convId: convId.uuidString, action: action, impact: impact, risk: risk)
        do {
            _ = try Activity<ApprovalAttributes>.request(
                attributes: attrs,
                content: .init(state: ApprovalAttributes.ContentState(answered: false),
                               staleDate: nil))
        } catch {
            // 锁屏活动起不来不影响卡片本身。
        }
    }

    @MainActor
    static func end() {
        for a in Activity<ApprovalAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
