import Foundation
import SwiftUI

enum AuditKind: String, Codable {
    case approval, decision, work, plan
}

enum AuditStatus: String, Codable {
    case allowed, denied, pending, done, planned
}

struct AuditRecord: Codable, Identifiable {
    var id = UUID()
    var date: Date = Date()
    var botId: String
    var botName: String
    var kind: AuditKind
    var title: String
    var detail: String
    var status: AuditStatus
}

/// 审核记录: everything the agents did or planned, plus every approval's
/// allow / deny / pending, searchable and filterable. The newest 200
/// records are kept on this device.
@MainActor
final class AuditStore: ObservableObject {
    static let key = "cn.lingyu.audit.v1"
    static let cap = 200
    @Published private(set) var records: [AuditRecord] = []

    init() { load() }

    func record(botId: String, botName: String, kind: AuditKind, title: String, detail: String, status: AuditStatus) {
        records.insert(AuditRecord(botId: botId, botName: botName, kind: kind, title: title, detail: detail, status: status), at: 0)
        if records.count > Self.cap {
            records = Array(records.prefix(Self.cap))
        }
        save()
    }

    func remove(id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    func clear() {
        records = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([AuditRecord].self, from: data) else { return }
        records = decoded
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(records), forKey: Self.key)
    }
}

extension DateFormatter {
    /// HH:mm:ss — chat message times and audit row timestamps.
    static let chatTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// yyyy-MM-dd HH:mm — audit detail and data export timestamps.
    static let auditTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}
