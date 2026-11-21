import SwiftUI
import UniformTypeIdentifiers
import Compression

/// 导入智能体: read a Grok Bot export zip on this phone, show what it
/// holds, and stop at the honest line — the import itself cannot run here.
///
/// Format (host `src/import/manifest.rs`, `export-skill.md`): a zip whose
/// root holds `codync-import.json` (format `codync-bot-import`, version 1)
/// or `openbot-import.json` / `openbot-transfer.json`. `agents` carry key,
/// name, title, description, avatar, skills (`agents/<key>/skills/<skill>/
/// SKILL.md`), routines, memories (up to 50 per agent, 500 chars each) and
/// workspace files (`agents/<key>/files/`, copied in as `imported/`);
/// `channels` are the group chats (lead first in `members`). Chats are not
/// carried over — only the facts distilled from them as memories. Limits
/// enforced by the host: 5000 entries, 500 MB inflated, manifest 8 MB,
/// 200 agents, 64 routines, 512 memories.
/// Live probe (probe_p4h.py, host 2.51.0): `previewImport` and
/// `importBots` exist but answer 403 "This can only be done at the
/// computer itself." — they take a path on the computer, and the phone
/// cannot call them. So this page parses locally for the preview and the
/// Import button stays disabled with that reason.
struct BotImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingImporter = false
    @State private var fileName: String?
    @State private var plan: BotImportPlan?
    @State private var parseError: String?

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("导入智能体")) {
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    explainerSection
                    pickSection
                    if let plan {
                        planSection(plan)
                    }
                    if let parseError {
                        CardSection(title: L("读不出来")) {
                            CardRow {
                                Text(parseError)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.danger)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    importSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(Palette.background)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.zip]
        ) { result in
            switch result {
            case .success(let url):
                readExport(from: url)
            case .failure:
                parseError = L("没选到文件，请重试。")
            }
        }
    }

    private var explainerSection: some View {
        CardSection(title: L("从哪里来")) {
            CardRow {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("导出文件是一个 zip：智能体与群聊的名字、说明、头像、技能、定时、记忆和工作区文件。聊天记录不跟着过来，只带记忆里的要点。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("先在有这些智能体的电脑上导出 zip，再传到这部手机上选文件。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var pickSection: some View {
        CardSection(title: L("导出文件")) {
            CardRow {
                Button(L("选择 zip 文件")) {
                    showingImporter = true
                }
                .font(.body)
                .foregroundStyle(Palette.text)
            }
            if let fileName {
                Hairline()
                CardRow {
                    Text(fileName)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private func planSection(_ plan: BotImportPlan) -> some View {
        Group {
            CardSection(title: L("将导入的内容")) {
                CardRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("来源：%@，共 %d 个智能体、%d 个群聊。", plan.sourceApp, plan.bots.count, plan.groups.count))
                            .font(.body)
                            .foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(L("文件里共 %d 个条目。", plan.entryCount))
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondary)
                    }
                }
                ForEach(plan.bots) { bot in
                    Hairline()
                    CardRow {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bot.name)
                                .font(.body)
                                .foregroundStyle(Palette.text)
                            Text(L("技能 %d 个 · 定时 %d 个 · 记忆 %d 条%@", bot.skillCount, bot.routineCount, bot.memoryCount, bot.hasFiles ? L(" · 含工作区文件") : ""))
                                .font(.subheadline)
                                .foregroundStyle(Palette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                ForEach(plan.groups) { group in
                    Hairline()
                    CardRow {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.name)
                                .font(.body)
                                .foregroundStyle(Palette.text)
                            Text(L("群聊 · %d 人 · 定时 %d 个 · 记忆 %d 条", group.memberCount, group.routineCount, group.memoryCount))
                                .font(.subheadline)
                                .foregroundStyle(Palette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if !plan.warnings.isEmpty {
                CardSection(title: L("注意")) {
                    ForEach(plan.warnings, id: \.self) { warning in
                        CardRow {
                            Text(warning)
                                .font(.subheadline)
                                .foregroundStyle(Palette.attention)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var importSection: some View {
        CardSection(title: L("导入")) {
            CardRow {
                VStack(alignment: .leading, spacing: 6) {
                    Button(L("导入")) {}
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.tertiary)
                        .disabled(true)
                    Text(L("导入要在电脑上完成：主机只接受本机调用，手机调不到导入方法。把 zip 传到电脑，在桌面端点导入智能体，或在电脑终端里用导入命令导入。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func readExport(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            parseError = L("打不开这个文件，请重试。")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else {
            parseError = L("读不到这个文件，请重试。")
            return
        }
        fileName = url.lastPathComponent
        let outcome = ZipExportReader.readPlan(from: data)
        plan = outcome.plan
        parseError = outcome.error
    }
}

/// What the preview shows. Not the host's plan: only what the zip itself
/// says, so nothing here can be mistaken for an import result.
struct BotImportPlan {
    var sourceApp: String
    var bots: [BotImportBot]
    var groups: [BotImportGroup]
    var warnings: [String]
    var entryCount: Int
}

struct BotImportBot: Identifiable {
    var id: String { key }
    var key: String
    var name: String
    var skillCount: Int
    var routineCount: Int
    var memoryCount: Int
    var hasFiles: Bool
}

struct BotImportGroup: Identifiable {
    var id: String { key }
    var key: String
    var name: String
    var memberCount: Int
    var routineCount: Int
    var memoryCount: Int
}

// MARK: - Manifest decoding (lenient: a bad agent is skipped, not fatal)

private struct ImportManifest: Decodable {
    var format: String?
    var version: Int?
    var source: ImportSource?
    var agents: [ImportAgent]?
    var channels: [ImportChannel]?
}

private struct ImportSource: Decodable {
    var app: String?
}

private struct ImportAgent: Decodable {
    var key: String?
    var name: String?
    var avatar: String?
    var skills: [String]?
    var routines: [ImportRoutine]?
    var oneTimeRoutines: [ImportRoutine]?
    var memories: [ImportMemory]?
    var files: String?
}

private struct ImportChannel: Decodable {
    var key: String?
    var name: String?
    var members: [String]?
    var routines: [ImportRoutine]?
    var memories: [ImportMemory]?
}

private struct ImportRoutine: Decodable {
    var name: String?
    var instruction: String?
}

private enum ImportMemory: Decodable {
    case text(String)

    var text: String {
        switch self {
        case .text(let value): return value
        }
    }

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            self = .text(value)
            return
        }
        let container = try decoder.container(keyedBy: ImportMemoryKeys.self)
        self = .text(try container.decode(String.self, forKey: .text))
    }

    private enum ImportMemoryKeys: String, CodingKey {
        case text
    }
}

// MARK: - Minimal zip reader (central directory + inflate)

/// Reads a zip far enough to find and parse the import manifest. Stored
/// entries are read raw; deflated entries are inflated with the Compression
/// framework (a raw deflate stream wrapped as zlib). Nothing is written.
enum ZipExportReader {
    private static let maxEntries = 5000
    private static let maxBytes = 500 * 1024 * 1024
    private static let maxManifest = 8 * 1024 * 1024

    /// Returns the plan, or the reason it could not be read. A plain tuple
    /// on purpose: the codebase only allows a fixed set of error types for
    /// the generic result wrapper, and a plain message is not one of them.
    static func readPlan(from data: Data) -> (plan: BotImportPlan?, error: String?) {
        guard data.count <= maxBytes else {
            return (nil, L("这个文件超过 500 MB，导不进来。"))
        }
        guard let directory = parseCentralDirectory(data) else {
            return (nil, L("这不是一个 zip 文件。"))
        }
        guard directory.entries.count <= maxEntries else {
            return (nil, L("这个文件里的条目超过 5000 个，导不进来。"))
        }
        let manifestNames = ["codync-import.json", "openbot-import.json", "openbot-transfer.json"]
        guard let manifestEntry = directory.entries.first(where: { entry in
            manifestNames.contains { entry.name == $0 || entry.name.hasSuffix("/" + $0) }
        }) else {
            return (nil, L("这不是智能体导出文件：里面没有导入清单。"))
        }
        let manifestName = manifestNames.first { manifestEntry.name == $0 || manifestEntry.name.hasSuffix("/" + $0) } ?? manifestNames[0]
        let prefix = String(manifestEntry.name.dropLast(manifestName.count))
        guard manifestEntry.size <= maxManifest else {
            return (nil, L("导入清单超过 8 MB，导不进来。"))
        }
        guard let manifestData = readEntry(data, manifestEntry) else {
            return (nil, L("导入清单读不出来。"))
        }
        guard let manifest = try? JSONDecoder().decode(ImportManifest.self, from: manifestData) else {
            return (nil, L("导入清单不是合法的 JSON。"))
        }
        // The host refuses a manifest whose format does not match its file.
        if let format = manifest.format,
           !["codync-bot-import", "openbot-agent-import", "openbot-instance-transfer"].contains(format) {
            return (nil, L("导入清单的格式不对，导不进来。"))
        }
        var warnings: [String] = []
        var bots: [BotImportBot] = []
        for raw in manifest.agents ?? [] {
            guard let key = raw.key, !key.isEmpty, let name = raw.name, !name.isEmpty else {
                warnings.append(L("跳过了一个没有名字或编号的智能体。"))
                continue
            }
            let routines = (raw.routines ?? []) + (raw.oneTimeRoutines ?? [])
            bots.append(BotImportBot(
                key: key,
                name: name,
                skillCount: raw.skills?.count ?? 0,
                routineCount: routines.count,
                memoryCount: raw.memories?.count ?? 0,
                hasFiles: raw.files != nil && directory.entries.contains { $0.name.hasPrefix(prefix + (raw.files ?? "")) }
            ))
        }
        var groups: [BotImportGroup] = []
        for raw in manifest.channels ?? [] {
            guard let key = raw.key, !key.isEmpty, let name = raw.name, !name.isEmpty else {
                warnings.append(L("跳过了一个没有名字或编号的群聊。"))
                continue
            }
            groups.append(BotImportGroup(
                key: key,
                name: name,
                memberCount: raw.members?.count ?? 0,
                routineCount: raw.routines?.count ?? 0,
                memoryCount: raw.memories?.count ?? 0
            ))
        }
        guard !bots.isEmpty else {
            return (nil, L("这个导出文件里没有能导入的智能体。"))
        }
        return (BotImportPlan(
            sourceApp: manifest.source?.app ?? L("未知来源"),
            bots: bots,
            groups: groups,
            warnings: warnings,
            entryCount: directory.entries.count
        ), nil)
    }

    private struct DirectoryEntry {
        var name: String
        var method: UInt16
        var compressedSize: Int
        var size: Int
        var localOffset: Int
    }

    private struct Directory {
        var entries: [DirectoryEntry]
    }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16? {
        guard offset + 2 <= data.count else { return nil }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        return UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }

    private static func parseCentralDirectory(_ data: Data) -> Directory? {
        // End of central directory: PK\x05\x06, in the last 64 KiB + 22 bytes.
        let searchStart = max(0, data.count - 65557)
        var eocd: Int?
        var index = data.count - 22
        while index >= searchStart {
            if data[index] == 0x50, data[index + 1] == 0x4B, data[index + 2] == 0x05, data[index + 3] == 0x06 {
                eocd = index
                break
            }
            index -= 1
        }
        guard let eocd,
              let cdSize = u32(data, eocd + 12),
              let cdOffset = u32(data, eocd + 16) else {
            return nil
        }
        var entries: [DirectoryEntry] = []
        var offset = Int(cdOffset)
        let end = min(data.count, Int(cdOffset) + Int(cdSize))
        while offset + 46 <= end {
            guard data[offset] == 0x50, data[offset + 1] == 0x4B,
                  data[offset + 2] == 0x01, data[offset + 3] == 0x02,
                  let method = u16(data, offset + 10),
                  let compressedSize = u32(data, offset + 20),
                  let size = u32(data, offset + 24),
                  let nameLen = u16(data, offset + 28),
                  let extraLen = u16(data, offset + 30),
                  let commentLen = u16(data, offset + 32),
                  let localOffset = u32(data, offset + 42) else {
                return nil
            }
            let nameStart = offset + 46
            let nameEnd = nameStart + Int(nameLen)
            guard nameEnd <= data.count,
                  let name = String(data: data[nameStart..<nameEnd], encoding: .utf8) else {
                return nil
            }
            entries.append(DirectoryEntry(
                name: name, method: method,
                compressedSize: Int(compressedSize), size: Int(size),
                localOffset: Int(localOffset)
            ))
            offset = nameEnd + Int(extraLen) + Int(commentLen)
        }
        return Directory(entries: entries)
    }

    private static func readEntry(_ data: Data, _ entry: DirectoryEntry) -> Data? {
        let offset = entry.localOffset
        guard offset + 30 <= data.count,
              data[offset] == 0x50, data[offset + 1] == 0x4B,
              data[offset + 2] == 0x03, data[offset + 3] == 0x04,
              let nameLen = u16(data, offset + 26),
              let extraLen = u16(data, offset + 28) else {
            return nil
        }
        let start = offset + 30 + Int(nameLen) + Int(extraLen)
        let end = start + entry.compressedSize
        guard end <= data.count else { return nil }
        let raw = data[start..<end]
        switch entry.method {
        case 0:
            return Data(raw)
        case 8:
            return inflate(Data(raw), expectedSize: entry.size)
        default:
            return nil
        }
    }

    private static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return Data() }
        var wrapped = Data([0x78, 0x01])
        wrapped.append(data)
        var output = Data(count: expectedSize)
        let decoded = output.withUnsafeMutableBytes { outPtr in
            wrapped.withUnsafeBytes { inPtr in
                compression_decode_buffer(
                    outPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    UInt(expectedSize),
                    inPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    UInt(wrapped.count),
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard Int(decoded) == expectedSize else { return nil }
        return output
    }
}
