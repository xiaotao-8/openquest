import Foundation

/// Host compatibility: Phase 1 targets the live host 2.50.0 (schema 8).
/// Older hosts are refused with a message; unknown versions count as new
/// (the `speaksThreads` gate in `HelloReply` follows the same rule).
enum Compatibility {
    static let minHostVersion = "2.50.0"

    /// Compares dotted versions numerically. Unparseable versions are
    /// treated as new (never block on a version string we cannot read).
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }
        guard !left.isEmpty, !right.isEmpty else { return .orderedSame }
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        return .orderedSame
    }

    static func isSupported(version: String) -> Bool {
        compare(version, minHostVersion) != .orderedAscending
    }

    /// Returns a user-facing message when the host is too old, else nil.
    static func unsupportedMessage(for hello: HelloReply) -> String? {
        guard !hello.version.isEmpty, !isSupported(version: hello.version) else {
            return nil
        }
        return L("这台电脑版本太旧（%@），请先更新到 %@ 或更新。", hello.version, minHostVersion)
    }
}
