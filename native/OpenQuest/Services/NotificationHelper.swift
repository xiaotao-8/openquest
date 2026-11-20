import Foundation
import UserNotifications

/// 本地通知（定时任务 + 提问卡后台 deferred 共用）：只发提醒，执行永远在 App 内做。
enum NotificationHelper {
    /// 第一次用通知功能时申请授权（用户点允许才发，不强求）。
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 按任务的重复规则排一条本地通知（到点响一声，用户点开 App 就执行）。
    static func schedule(task: ScheduledTask) {
        requestAuthorization()
        let center = UNUserNotificationCenter.current()
        let id = "oq-task-\(task.id.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard task.enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "定时任务：\(task.title)"
        content.body = task.prompt
        let trigger: UNNotificationTrigger?
        let cal = Calendar.current
        switch task.repeatKind {
        case "daily", "weekly":
            var comps = cal.dateComponents([.hour, .minute], from: task.nextFire)
            if task.repeatKind == "weekly" {
                // 任务里周一=1；Calendar 里周日=1。
                let wd = task.weekdays.first ?? 1
                comps.weekday = wd % 7 + 1
            }
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        case "every":
            let interval = TimeInterval(max(task.everyMinutes, 1) * 60)
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: true)
        default:
            let interval = max(task.nextFire.timeIntervalSinceNow, 5)
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        }
        guard let trigger else { return }
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(req)
    }

    static func cancel(taskId: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["oq-task-\(taskId.uuidString)"])
    }

    /// 立刻发一条提醒（如提问卡在后台等回答）。
    static func notifyNow(title: String, body: String, identifier: String) {
        requestAuthorization()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
