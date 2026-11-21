import CryptoKit
import Foundation

/// Strict base64url (RFC 4648 §5, no padding) plus SHA-256 and big-endian u64.
/// No crypto decisions live here — only byte encoding.
/// Wire-protocol string constants ("codync/…") are protocol bytes and must stay
/// verbatim; they never appear in user-visible strings.
enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func encode(_ bytes: [UInt8]) -> String {
        encode(Data(bytes))
    }

    /// Strict decode: rejects `+`, `/`, `=` and lengths where `count % 4 == 1`.
    static func decode(_ string: String) -> Data? {
        guard !string.isEmpty else { return Data() }
        if string.count % 4 == 1 { return nil }
        for scalar in string.unicodeScalars {
            let c = scalar.value
            let ok = (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
                || (c >= 48 && c <= 57) || c == 45 || c == 95
            if !ok { return nil }
        }
        var padded = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded.append("=") }
        return Data(base64Encoded: padded)
    }
}

enum Digest {
    static func sha256(_ parts: Data...) -> Data {
        var hasher = SHA256()
        for part in parts { hasher.update(data: part) }
        return Data(hasher.finalize())
    }

    static func sha256(_ parts: [Data]) -> Data {
        var hasher = SHA256()
        for part in parts { hasher.update(data: part) }
        return Data(hasher.finalize())
    }
}

enum U64 {
    static func bigEndian(_ value: UInt64) -> Data {
        var big = value.bigEndian
        return Data(bytes: &big, count: 8)
    }

    static func fromBigEndian(_ data: Data) -> UInt64? {
        guard data.count == 8 else { return nil }
        var value: UInt64 = 0
        for byte in data { value = (value << 8) | UInt64(byte) }
        return value
    }
}
