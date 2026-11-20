import Foundation

/// 应用运行日志（设置 → 日志）：真实记、真实读，不是占位。
/// 记启动、云电脑连通结果、聊天出错等关键事件；上限 300 条，存 Documents/app-log.json。
/// 写在 utility 串行队列上，不堵界面；读是小文件同步读。
enum LogStore {
    struct Entry: Codable, Identifiable {
        var id: UUID = UUID()
        var time: Date = Date()
        var tag: String
        var message: String
    }

    private static let fileName = "app-log.json"
    private static let maxEntries = 300
    private static let queue = DispatchQueue(label: "oq.log", qos: .utility)

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    static func append(_ tag: String, _ message: String) {
        let entry = Entry(tag: tag, message: message)
        queue.async {
            var list = load()
            list.append(entry)
            if list.count > maxEntries { list.removeFirst(list.count - maxEntries) }
            try? JSONEncoder().encode(list).write(to: fileURL, options: .atomic)
        }
    }

    /// 最新在前。
    static func entries() -> [Entry] {
        load().sorted { $0.time > $1.time }
    }

    static func clear() {
        queue.async { try? FileManager.default.removeItem(at: fileURL) }
    }

    private static func load() -> [Entry] {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return list
    }
}
