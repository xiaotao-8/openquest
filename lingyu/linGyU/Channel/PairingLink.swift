import Foundation

/// Pairing link (`codync://pair?v=3…`) parse + validation, short-code
/// normalisation, offer id and the 6-digit pair-check code.
/// Short codes resolve via a cloud service linGyU Phase 1 does not have, so
/// a bare short code is never expanded locally — the UI must offer the
/// full-link path instead (see PairingProblem.unresolvableShortCode).
struct PairingLink {
    let name: String
    let computerId: String
    let signKey: Data // 32 bytes, host Ed25519 public key
    let boxKey: Data // 32 bytes, host X25519 public key
    let code: Data // 16 bytes, one-time pairing code
    let codeBase64URL: String
    let urls: [String]
    let cloud: String?
    let offerId: String

    var computer: Computer {
        Computer(from: self)
    }

    static func parse(_ text: String) -> Result<PairingLink, PairingProblem> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "codync", url.host == "pair" else {
            return .failure(.invalid)
        }
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = parts.queryItems else {
            return .failure(.invalid)
        }
        var query: [String: String] = [:]
        for item in items { query[item.name] = item.value ?? "" }
        guard query["v"] == "3" else { return .failure(.outdatedHost) }
        guard let id = query["id"], !id.isEmpty,
              let skText = query["sk"], let sk = Base64URL.decode(skText), sk.count == 32,
              let bkText = query["bk"], let bk = Base64URL.decode(bkText), bk.count == 32,
              let codeText = query["code"], let code = Base64URL.decode(codeText), code.count == 16
        else {
            return .failure(.invalid)
        }
        guard ChannelCrypto.computerId(hostSignPub: sk) == id else {
            return .failure(.invalid)
        }
        let urls = (query["urls"] ?? "")
            .split(separator: ",")
            .map(String.init)
            .filter { isDirectURL($0) }
        let cloud = query["cloud"].flatMap { $0.isEmpty ? nil : $0 }
        guard !urls.isEmpty || cloud != nil else { return .failure(.invalid) }
        let name = (query["name"] ?? "").removingPercentEncoding ?? ""
        let link = PairingLink(
            name: name.isEmpty ? "My computer" : name,
            computerId: id, signKey: sk, boxKey: bk, code: code,
            codeBase64URL: codeText, urls: Array(urls.prefix(16)), cloud: cloud,
            offerId: ChannelCrypto.offerId(codeBytes: code))
        return .success(link)
    }

    static func isDirectURL(_ string: String) -> Bool {
        guard let url = URL(string: string),
              (url.scheme == "http" || url.scheme == "https"),
              let host = url.host, !host.isEmpty else { return false }
        return true
    }

    /// Normalises a typed short code to `QRTX-4821` form, or nil if invalid.
    static func normaliseShortCode(_ text: String) -> String? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
        guard cleaned.count == 8 else { return nil }
        let letters = cleaned.prefix(4)
        let digits = cleaned.suffix(4)
        guard letters.allSatisfy({ $0.isLetter && $0.isASCII }),
              digits.allSatisfy({ $0.isNumber && $0.isASCII }) else { return nil }
        return "\(letters)-\(digits)"
    }

    static func pairCheckCode(devicePub: Data, hostSignPub: Data) -> String {
        ChannelCrypto.pairCheckCode(devicePub: devicePub, hostSignPub: hostSignPub)
    }
}

enum PairingProblem: Error {
    case invalid
    case outdatedHost
    case unresolvableShortCode
    case pairingClosed
    case rateLimited
    case unauthorized
    case timeout
}
