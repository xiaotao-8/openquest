import Foundation

/// 记忆（FishPocket/Minis 式条目制）：存在服务器上该智能体工作目录的 MEMORY.md 里，
/// 一行一条；历史快照在 MEMORY.history.md 里。走 ServerClient.exec 读写，
/// 不用改服务器（exec 已有，工作目录按智能体的 workDir 前缀 cd）。
struct MemoryEntry: Identifiable, Equatable {
    var id: Int              // 行号（文件里的第几行）
    var text: String
    var by: String           // user / self
    var scope: String        // bot / team
    var topic: String
    var added: String        // 日期
}

enum MemoryStore {
    private static func memPath(workDir: String) -> String {
        workDir.isEmpty ? "MEMORY.md" : "\(workDir)/MEMORY.md"
    }

    private static func histPath(workDir: String) -> String {
        workDir.isEmpty ? "MEMORY.history.md" : "\(workDir)/MEMORY.history.md"
    }

    /// exec 在智能体工作目录里跑；workDir 非空时先 cd 过去（私有智能体隔离用）。
    private static func run(agentId: String, workDir: String, server: ServerConfig,
                            command: String) async throws -> String {
        let cmd = workDir.isEmpty ? command : "cd \(shellQuote(workDir)) && \(command)"
        let r = try await ServerClient(config: server).exec(agentId: agentId, command: cmd)
        return r.stdout
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// base64 写文件（内容里有引号也不怕）。
    private static func writeFile(agentId: String, workDir: String, server: ServerConfig,
                                  path: String, content: String) async throws {
        let b64 = Data(content.utf8).base64EncodedString()
        _ = try await run(agentId: agentId, workDir: workDir, server: server,
                          command: "printf '%s' '\(b64)' | base64 -d > \(shellQuote(path))")
    }

    /// 读全部条目（文件没有就是空）。
    static func load(agentId: String, workDir: String, server: ServerConfig) async -> [MemoryEntry] {
        guard let out = try? await run(agentId: agentId, workDir: workDir, server: server,
                                       command: "cat \(shellQuote(memPath(workDir: workDir))) 2>/dev/null || true") else {
            return []
        }
        return parse(out)
    }

    /// 一行一条：日期 | by | scope | topic | 正文。
    static func parse(_ text: String) -> [MemoryEntry] {
        var out: [MemoryEntry] = []
        for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            let parts = line.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 5 else { continue }
            out.append(MemoryEntry(id: i, text: parts[4], by: parts[1],
                                   scope: parts[2], topic: parts[3], added: parts[0]))
        }
        return out
    }

    private static func serialize(_ entries: [MemoryEntry]) -> String {
        entries.map { "\($0.added) | \($0.by) | \($0.scope) | \($0.topic) | \($0.text)" }
            .joined(separator: "\n") + (entries.isEmpty ? "" : "\n")
    }

    /// 写之前先把旧内容追加一份快照到历史文件（恢复用）。
    private static func snapshot(agentId: String, workDir: String, server: ServerConfig) async {
        guard let old = try? await run(agentId: agentId, workDir: workDir, server: server,
                                       command: "cat \(shellQuote(memPath(workDir: workDir))) 2>/dev/null || true"),
              !old.isEmpty else { return }
        let stamp = Self.stamp()
        let block = "## \(stamp)\n\(old)\n"
        let b64 = Data(block.utf8).base64EncodedString()
        _ = try? await run(agentId: agentId, workDir: workDir, server: server,
                           command: "printf '%s' '\(b64)' | base64 -d >> \(shellQuote(histPath(workDir: workDir)))")
    }

    static func add(agentId: String, workDir: String, server: ServerConfig,
                    text: String, by: String, scope: String, topic: String) async -> Bool {
        let clean = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: "/")
        var entries = await load(agentId: agentId, workDir: workDir, server: server)
        await snapshot(agentId: agentId, workDir: workDir, server: server)
        entries.append(MemoryEntry(id: entries.count, text: clean, by: by,
                                   scope: scope, topic: topic, added: stamp()))
        do {
            try await writeFile(agentId: agentId, workDir: workDir, server: server,
                                path: memPath(workDir: workDir), content: serialize(entries))
            return true
        } catch {
            return false
        }
    }

    /// 忘掉一条（按行号删）。
    static func forget(agentId: String, workDir: String, server: ServerConfig,
                       entryId: Int) async -> Bool {
        var entries = await load(agentId: agentId, workDir: workDir, server: server)
        guard entries.indices.contains(entryId) else { return false }
        await snapshot(agentId: agentId, workDir: workDir, server: server)
        entries.remove(at: entryId)
        do {
            try await writeFile(agentId: agentId, workDir: workDir, server: server,
                                path: memPath(workDir: workDir), content: serialize(entries))
            return true
        } catch {
            return false
        }
    }

    /// 历史快照列表：每条一个时间戳 + 当时的条目数。
    static func history(agentId: String, workDir: String, server: ServerConfig) async -> [(stamp: String, count: Int, content: String)] {
        guard let out = try? await run(agentId: agentId, workDir: workDir, server: server,
                                       command: "cat \(shellQuote(histPath(workDir: workDir))) 2>/dev/null || true"),
              !out.isEmpty else { return [] }
        var snaps: [(String, Int, String)] = []
        var curStamp = ""
        var curLines: [String] = []
        for line in out.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## ") {
                if !curStamp.isEmpty {
                    snaps.append((curStamp, curLines.filter { !$0.isEmpty }.count,
                                  curLines.joined(separator: "\n")))
                }
                curStamp = String(line.dropFirst(3))
                curLines = []
            } else {
                curLines.append(String(line))
            }
        }
        if !curStamp.isEmpty {
            snaps.append((curStamp, curLines.filter { !$0.isEmpty }.count,
                          curLines.joined(separator: "\n")))
        }
        return snaps.reversed()
    }

    /// 恢复到某一份快照（先给当前内容也留一份快照）。
    static func restore(agentId: String, workDir: String, server: ServerConfig,
                        content: String) async -> Bool {
        await snapshot(agentId: agentId, workDir: workDir, server: server)
        do {
            try await writeFile(agentId: agentId, workDir: workDir, server: server,
                                path: memPath(workDir: workDir), content: content)
            return true
        } catch {
            return false
        }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date())
    }
}
