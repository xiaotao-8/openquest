import Foundation
import CryptoKit
import SwiftUI

/// The three-file user model (Soul / Memory / Identity), stored as real
/// Markdown files in Documents/identity/. Nothing is pre-filled: the files
/// start empty and the user writes them; the app reads them back on launch.
///
/// The Soul file is the highest-priority instruction set. If it changed
/// since the app last wrote it, `soulChangedExternally` is set so the Soul
/// page can warn the user instead of silently overwriting it.
@MainActor
final class IdentityStore: ObservableObject {
    static let directoryName = "identity"
    static let soulFile = "soul.md"
    static let memoryFile = "memory.md"
    static let identityFile = "identity.md"
    private static let soulHashKey = "cn.lingyu.soul.lastHash"

    @Published private(set) var soul = ""
    @Published private(set) var memory = ""
    @Published private(set) var identity = ""
    @Published private(set) var soulChangedExternally = false

    private var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.directoryName, isDirectory: true)
    }

    /// The assistant's structured identity, parsed out of IDENTITY.md:
    /// first `# ` line is the name, `风格：` the vibe, `简介：` the tagline.
    var identityName: String { parsedIdentity.name }
    var identityVibe: String { parsedIdentity.vibe }
    var identityTagline: String { parsedIdentity.tagline }
    var identityBody: String { parsedIdentity.body }

    private var parsedIdentity: (name: String, vibe: String, tagline: String, body: String) {
        var name = ""
        var vibe = ""
        var tagline = ""
        var bodyLines: [String] = []
        for line in identity.components(separatedBy: "\n") {
            if line.hasPrefix("# ") && name.isEmpty {
                name = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("风格：") {
                vibe = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("简介：") {
                tagline = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else {
                bodyLines.append(line)
            }
        }
        return (name, vibe, tagline, bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func load() {
        soul = read(Self.soulFile)
        memory = read(Self.memoryFile)
        identity = read(Self.identityFile)
        if let data = try? Data(contentsOf: directory.appendingPathComponent(Self.soulFile)),
           let lastHash = UserDefaults.standard.string(forKey: Self.soulHashKey) {
            soulChangedExternally = sha256Hex(data) != lastHash
        } else {
            soulChangedExternally = false
        }
    }

    func saveSoul(_ text: String) {
        write(text, file: Self.soulFile)
        soul = text
        if let data = text.data(using: .utf8) {
            UserDefaults.standard.set(sha256Hex(data), forKey: Self.soulHashKey)
        }
        soulChangedExternally = false
    }

    /// The user reviewed the external change and accepts it as the new baseline.
    func acknowledgeExternalSoulChange() {
        if let data = try? Data(contentsOf: directory.appendingPathComponent(Self.soulFile)) {
            UserDefaults.standard.set(sha256Hex(data), forKey: Self.soulHashKey)
        }
        soulChangedExternally = false
    }

    func saveMemory(_ text: String) {
        write(text, file: Self.memoryFile)
        memory = text
    }

    func saveIdentity(name: String, vibe: String, tagline: String, body: String) {
        var lines: [String] = []
        lines.append("# \(name)")
        lines.append("风格：\(vibe)")
        lines.append("简介：\(tagline)")
        lines.append("")
        lines.append(body)
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        write(text, file: Self.identityFile)
        identity = text
    }

    /// Append imported text to MEMORY.md, separated with a dated marker.
    func appendToMemory(_ text: String) {
        let marker = "—— \(L("导入于")) \(DateFormatter.identityImport.string(from: Date())) ——"
        let combined = memory.isEmpty ? "\(marker)\n\(text)" : "\(memory)\n\n\(marker)\n\(text)"
        saveMemory(combined)
    }

    /// Clear MEMORY.md entirely (user-confirmed forget).
    func forgetMemory() {
        saveMemory("")
    }

    private func read(_ file: String) -> String {
        (try? String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)) ?? ""
    }

    private func write(_ text: String, file: String) {
        let dir = directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? text.write(to: dir.appendingPathComponent(file), atomically: true, encoding: .utf8)
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private extension DateFormatter {
    static let identityImport: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}
