import Foundation

/// One decoded `ev` from the events subscription. Unknown types are skipped
/// (they still count toward the catch-up total). A bad `bot`/`entry` row is
/// `.undecodable`, never a stream crash.
enum HostEvent {
    case hello(rev: Int64, catchUp: Int, hostId: String)
    case icons(icons: [String: JSONValue], revision: Int)
    case bot(Bot)
    case botDeleted(id: String, rev: Int64)
    case entry(Entry)
    case threadEntry(threadId: String, entry: Entry)
    case usage(JSONValue)
    case screen(JSONValue)
    case artifact(JSONValue)
    case network(JSONValue)
    case name(String)
    case autoOrder(Bool)
    case resync
    case callCue
    case undecodable(type: String)
    case skipped

    static func parse(_ data: Data) -> HostEvent {
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = envelope["type"] as? String else {
            return .skipped
        }
        let rev = (envelope["rev"] as? NSNumber)?.int64Value ?? 0
        switch type {
        case "hello":
            let hostId = envelope["hostId"] as? String ?? ""
            let catchUp = (envelope["catchUp"] as? NSNumber)?.intValue ?? 0
            return .hello(rev: rev, catchUp: catchUp, hostId: hostId)
        case "icons":
            let revision = (envelope["iconsRevision"] as? NSNumber)?.intValue ?? 0
            var icons: [String: JSONValue] = [:]
            if let raw = envelope["icons"],
               let iconData = try? JSONSerialization.data(withJSONObject: raw),
               let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: iconData) {
                icons = decoded
            }
            return .icons(icons: icons, revision: revision)
        case "bot", "botDeleted":
            guard let raw = envelope["bot"],
                  let botData = try? JSONSerialization.data(withJSONObject: raw) else {
                return .undecodable(type: "bot")
            }
            if let stub = try? JSONSerialization.jsonObject(with: botData) as? [String: Any],
               stub["deleted"] as? Bool == true {
                let id = stub["id"] as? String ?? ""
                let stubRev = (stub["rev"] as? NSNumber)?.int64Value ?? rev
                return .botDeleted(id: id, rev: stubRev)
            }
            guard let bot = try? JSONDecoder().decode(Bot.self, from: botData), !bot.id.isEmpty else {
                return .undecodable(type: "bot")
            }
            return .bot(bot)
        case "entry":
            guard let raw = envelope["entry"],
                  let entryData = try? JSONSerialization.data(withJSONObject: raw),
                  let entry = try? JSONDecoder().decode(Entry.self, from: entryData),
                  !entry.id.isEmpty else {
                return .undecodable(type: "entry")
            }
            return .entry(entry)
        case "threadEntry", "taskEntry":
            // Live host 2.50.0 sends `taskEntry`; 2.51.0-era sends `threadEntry`.
            let threadId = envelope["thread"] as? String ?? envelope["task"] as? String ?? ""
            guard let raw = envelope["entry"],
                  let entryData = try? JSONSerialization.data(withJSONObject: raw),
                  let entry = try? JSONDecoder().decode(Entry.self, from: entryData),
                  !entry.id.isEmpty else {
                return .undecodable(type: "entry")
            }
            return .threadEntry(threadId: threadId, entry: entry)
        case "usage":
            return .usage(jsonValue(of: envelope["usage"]))
        case "screen":
            return .screen(jsonValue(of: envelope["screen"]))
        case "artifact":
            return .artifact(jsonValue(of: envelope["artifact"]))
        case "network":
            return .network(jsonValue(of: envelope["network"]))
        case "name":
            return .name(envelope["name"] as? String ?? "")
        case "autoOrder":
            return .autoOrder(envelope["enabled"] as? Bool ?? false)
        case "resync":
            return .resync
        case "call":
            return .callCue
        default:
            return .skipped
        }
    }

    private static func jsonValue(of raw: Any?) -> JSONValue {
        guard let raw,
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .null
        }
        return value
    }
}
