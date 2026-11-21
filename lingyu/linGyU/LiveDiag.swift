import Foundation
import SwiftUI

/// Live-preview diagnostics (Phase 1 only): an on-screen card so a
/// screenshot IS the evidence, a LogStore mirror (About → Log), and a
/// sandbox log file the CI script can cat into the build log.
///
/// Only shown when the app was launched with `-PreviewPairing` (live mode),
/// so the seeded preview screenshots are untouched. All lines are plain
/// technical English, no user-facing copy, no secrets: never record the
/// pairing blob or any key — only lengths, counts, and host versions.
@MainActor
final class LiveDiag: ObservableObject {
    @Published private(set) var lines: [String] = []
    private let cap = 10

    private var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("live-diag.log")
    }

    func record(_ message: String) {
        let line = "\(LiveDiag.timeStamp()) \(message)"
        lines.append(line)
        if lines.count > cap { lines.removeFirst(lines.count - cap) }
        LogStore.record(message)
        appendToFile(line)
    }

    private func appendToFile(_ line: String) {
        guard let url = fileURL else { return }
        let data = Data((line + "\n").utf8)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                _ = try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            // Diagnostics must never break the app; the on-screen card is
            // the primary evidence, the file is a bonus.
        }
    }

    private static func timeStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}

/// The on-screen diagnostics card, top-anchored so it never covers the
/// chat composer. Shown only in live preview mode.
struct LiveDiagOverlayView: View {
    @ObservedObject var diag: LiveDiag
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("LIVE DIAG")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                Spacer()
                Text(statusLine)
                    .font(.system(.caption2, design: .monospaced))
            }
            .foregroundStyle(.white)
            ForEach(diag.lines, id: \.self) { line in
                Text(line)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var statusLine: String {
        let connector = store.connector
        let hello = connector.hello.map { "hello v\($0.version)" } ?? "no-hello"
        return "\(connector.isPaired ? "paired" : "unpaired") \(hello) bots=\(connector.mirror.bots.count)"
    }
}
