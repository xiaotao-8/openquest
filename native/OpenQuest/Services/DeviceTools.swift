import Foundation
import EventKit
import Photos
import Contacts
import CoreLocation
import UIKit

/// 本机能力（FishPocket 式，一能力一工具）：只有设置里开着的能力才会进模型工具表；
/// 真用时还要过系统授权，拒绝就如实报没拿到授权，不糊弄。
enum DeviceTools {
    // MARK: 日历 / 提醒（EventKit）

    static func addCalendarEvent(title: String, startISO: String,
                                 durationMinutes: Int, notes: String) async -> String {
        let store = EKEventStore()
        do {
            let granted = try await store.requestAccess(to: .event)
            guard granted else { return "没拿到日历授权：去系统设置里打开" }
        } catch {
            return "日历授权失败：\(error.localizedDescription)"
        }
        let formatter = ISO8601DateFormatter()
        guard let start = formatter.date(from: startISO) ?? Self.looseDate(startISO) else {
            return "时间看不懂：要 ISO8601，如 2026-11-21T09:00:00+08:00"
        }
        let ev = EKEvent(eventStore: store)
        ev.title = title
        ev.startDate = start
        ev.endDate = start.addingTimeInterval(TimeInterval(max(durationMinutes, 1) * 60))
        ev.notes = notes.isEmpty ? nil : notes
        ev.calendar = store.defaultCalendarForNewEvents
        do {
            try store.save(ev, span: .thisEvent)
            return "已加到日历：「\(title)」，\(Self.shortDate(start))"
        } catch {
            return "写日历失败：\(error.localizedDescription)"
        }
    }

    static func addReminder(title: String, notes: String) async -> String {
        let store = EKEventStore()
        do {
            let granted = try await store.requestAccess(to: .reminder)
            guard granted else { return "没拿到提醒事项授权：去系统设置里打开" }
        } catch {
            return "提醒授权失败：\(error.localizedDescription)"
        }
        let item = EKReminder(eventStore: store)
        item.title = title
        item.notes = notes.isEmpty ? nil : notes
        item.calendar = store.defaultCalendarForNewReminders()
        do {
            try store.save(item, commit: true)
            return "已加到提醒事项：「\(title)」"
        } catch {
            return "写提醒失败：\(error.localizedDescription)"
        }
    }

    // MARK: 照片（只读数量和时间，不拿原图）

    static func recentPhotos() async -> String {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .denied || status == .restricted {
            return "没拿到照片授权：去系统设置里打开"
        }
        if status == .notDetermined {
            let new = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            if new == .denied || new == .restricted {
                return "没拿到照片授权：去系统设置里打开"
            }
        }
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.fetchLimit = 5
        let assets = PHAsset.fetchAssets(with: .image, options: opts)
        let total = PHAsset.fetchAssets(with: .image, options: nil).count
        var lines = ["相册里共有 \(total) 张照片。最近的："]
        assets.enumerateObjects { a, _, _ in
            if let d = a.creationDate {
                lines.append("- \(Self.shortDate(d))")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: 剪贴板

    static func readClipboard() async -> String {
        await MainActor.run {
            let text = UIPasteboard.general.string ?? ""
            return text.isEmpty ? "剪贴板是空的" : "剪贴板内容：\n\(text)"
        }
    }

    static func writeClipboard(_ text: String) async -> String {
        await MainActor.run {
            UIPasteboard.general.string = text
            return "已写到剪贴板"
        }
    }

    // MARK: 位置（读一次）

    static func currentLocation() async -> String {
        let status = CLLocationManager.authorizationStatus()
        if status == .denied || status == .restricted {
            return "没拿到位置授权：去系统设置里打开"
        }
        let manager = CLLocationManager()
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        let holder = LocationHolder()
        return await withCheckedContinuation { cont in
            holder.onResult = { cont.resume(returning: $0) }
            manager.delegate = holder
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.requestLocation()
            // 15 秒没回就当拿不到（定位关了/信号差），不等死。
            Task {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                holder.timeout()
            }
        }
    }

    // MARK: 通讯录（按名字查）

    static func searchContacts(name: String) async -> String {
        let store = CNContactStore()
        do {
            let granted = try await store.requestAccess(for: .contacts)
            guard granted else { return "没拿到通讯录授权：去系统设置里打开" }
        } catch {
            return "通讯录授权失败：\(error.localizedDescription)"
        }
        let keys: [CNKeyDescriptor] = [CNContactGivenNameKey as CNKeyDescriptor,
                                        CNContactFamilyNameKey as CNKeyDescriptor,
                                        CNContactPhoneNumbersKey as CNKeyDescriptor]
        let predicate = CNContact.predicateForContacts(matchingName: name)
        do {
            let found = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
            guard !found.isEmpty else { return "通讯录里没找到「\(name)」" }
            let lines = found.prefix(5).map { c in
                let phones = c.phoneNumbers.map { $0.value.stringValue }.joined(separator: "、")
                return "\(c.familyName)\(c.givenName)\(phones.isEmpty ? "" : "：\(phones)")"
            }
            return lines.joined(separator: "\n")
        } catch {
            return "查通讯录失败：\(error.localizedDescription)"
        }
    }

    // MARK: 小工具

    private static func looseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        for fmt in ["yyyy-MM-dd HH:mm", "yyyy/MM/dd HH:mm", "yyyy-MM-dd'T'HH:mm"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    private static func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: d)
    }
}

/// 定位一次请求的 delegate：成功或失败都只回一次。
private final class LocationHolder: NSObject, CLLocationManagerDelegate {
    var onResult: ((String) -> Void)?
    private var done = false

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !done, let loc = locations.last else { return }
        done = true
        onResult?("当前位置：纬度 \(String(format: "%.5f", loc.coordinate.latitude))，经度 \(String(format: "%.5f", loc.coordinate.longitude))")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard !done else { return }
        done = true
        onResult?("取位置失败：\(error.localizedDescription)")
    }

    func timeout() {
        guard !done else { return }
        done = true
        onResult?("取位置超时：可能没开定位服务")
    }
}
