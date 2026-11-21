import AVFoundation
import Foundation

/// Free online neural voice (Microsoft Edge readaloud endpoint), no API key.
///
/// The app's ONLY voice: Xiaoxiao (zh-CN-XiaoxiaoNeural, female), free,
/// online. There is no voice picker, no second voice, no offline model.
/// It is NOT DeepSeek's voice: DeepSeek's TTS is a paid API (stella/tide)
/// and the user has ruled that out ("no calls, no money"). Xiaoxiao is the
/// closest free voice by ear; the settings page must say so in plain words.
///
/// Edge needs the network. When there is no network (or Edge fails), the
/// caller (VoiceStore) skips the sentence silently: no system voice, no
/// offline model, no error popup. That is the user's decision
/// (2026-11-22: Edge throughout, silent when offline).
///
/// The endpoint is UNOFFICIAL (Edge's internal endpoint, not a public API):
/// no SLA, Microsoft may change or withdraw it at any time. If it breaks,
/// the caller skips the sentence silently — there is no fallback voice
/// of any kind. Do not add one back.
///
/// Provenance (2026-11-22, see `EDGE_TTS_PROOF.md` in the same directory):
/// - Synthesis + voice list verified live with edge-tts 7.3.1 and with a
///   hand-rolled WebSocket client using exactly this protocol.
/// - SSML whitelist: ONLY `<voice>` + `<prosody>` are accepted. `mstts:express-as`
///   styles (3 variants) and `<break>` (2 variants) are silently rejected:
///   the server sends `turn.start`, then closes the connection with zero
///   audio and no error frame. Do not add them back.
/// - `Sec-MS-GEC` is REQUIRED: without it the WebSocket handshake is 403.
///   `EdgeDRM` below is a transliteration of edge-tts `drm.py` (custom
///   SHA-256 variant + CS64). It is the highest-risk part of this file:
///   it was NOT compiled on this VM (no Xcode here). Merge step one is the
///   unit test in the comment block at the end of this file.
///
/// No new permission is needed: microphone / speech-recognition are already
/// declared for calls. This file only uses the network.
enum EdgeTTS {

    // MARK: - Endpoint (one place; if Microsoft moves it, change it here)

    /// WebSocket synthesis endpoint (readaloud). The query items are added
    /// per connection in `Synthesizer` (ConnectionId + Sec-MS-GEC).
    static let wssBaseURL = "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1"

    /// The Edge client's public fixed token, as shipped in the open-source
    /// edge-tts package (MIT). It is a client identifier, NOT a user key:
    /// every Edge browser sends the same value. No user credential lives here.
    static let userAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" +
        " (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0"
    static let origin = "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold"

    /// The audio the service returns: MP3, 48 kbps CBR, 24 kHz, mono.
    static let outputFormat = "audio-24khz-48kbitrate-mono-mp3"

    /// First-audio timeout. The VM's first connection once took ~32 s
    /// (egress-proxy warm-up); the phone should be faster, but do not set
    /// this below 30 s or the first call of the day will spuriously fail.
    static let firstAudioTimeout: TimeInterval = 30
    static let wholeSentenceTimeout: TimeInterval = 60

        // ---- Machine-generated from edge-tts 7.3.1 drm.py / constants.py ----
    // Do NOT hand-edit hex values. Regenerate with /tmp/gen_constants.py.
    static let trustedClientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    static let chromiumVersion = "143.0.3650.75"
    static let secMsGecVersion = "2-143.0.3650.75"
    static let sha256Initial: [UInt32] = [
        0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
    ]
    static let sha256State: [UInt32] = [
        0xFD9FBEA2, 0x91243CE7, 0xBE499094, 0xCD2E1E0A, 0x6C006F49, 0x04BD35AB, 0xFEB0A7E4, 0x03EFFBD2,
    ]
    static let sha256Schedule: [UInt32] = [
        0xEB24BF9E, 0x1558691F, 0xA0C09EE2, 0x0CFA32BA, 0xA622EE8C, 0xD1DD9491, 0xC0DD25A0,
        0xF9E70AB6, 0xF0C31573, 0x7058CE4E, 0x7188E606, 0x00E5AB33, 0xD258B060, 0x72766564,
    ]
    static let sha256RoundConstants: [UInt32] = [
        0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5,
        0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
        0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3,
        0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
        0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC,
        0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
        0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7,
        0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
        0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13,
        0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
        0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3,
        0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
        0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5,
        0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
        0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208,
        0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
    ]
    static let sha256BlockConstants: [UInt32] = [
        0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5,
        0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
        0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3,
        0x72BE5D74, 0x80DEB1FE, 0xC9DC06A7, 0xC19BF174,
        0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC,
        0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
        0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7,
        0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
        0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13,
        0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
        0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3,
        0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
        0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5,
        0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
        0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208,
        0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
    ]
    static let sha256Adjustment: UInt32 = 0xC9DC06A7
    static let sha256Sigma0Adjustment: UInt32 = 0x059C0B80
    static let sha256Sigma1Adjustment: UInt32 = 0x000B92C0
    static let cs64Factor: UInt32 = 0x82893933
    static let cs64Adjustment0: UInt32 = 0xF2F90B1A
    static let cs64Adjustment1: UInt32 = 0x0B1A0000
    static let cs64Coefficients: [(UInt32, UInt32)] = [
        (0xE82E91B1, 0xB32700D0), (0x44DE24C6, 0x88DFF51D),
        (0x3BEB65BC, 0x29514038), (0xC89C5933, 0xB328CBDF),
        (0x8D1EC211, 0xD405B4D5), (0x314EF5D5, 0x26E55F3C),
        (0xE92491B1, 0x607801C6), (0xF0A5B9D5, 0x82B2C1FB),
        (0x06064CF3, 0xFA51A3DA), (0xDA79FA60, 0x207CC464),
        (0xBED20560, 0x3C3C74F3), (0x89F9C9F8, 0xD2D14B61),
        (0x35FA38C6, 0xBB04A2C1), (0xCB49E3C6, 0xC5626167),
    ]

    // MARK: - Voices

    /// The one and only voice. Female, VoiceTag: Novel / Warm (from voices/list).
    enum Voice: String {
        case xiaoxiao = "zh-CN-XiaoxiaoNeural"

        static let `default` = Voice.xiaoxiao
    }

    /// Maps the stored AVSpeech-style rate (VoicePrefs.rate: 0.42 slow,
    /// 0.50 normal, 0.56 fast) to an Edge prosody rate. Kept coarse on
    /// purpose: Xiaoxiao's own prosody carries the expression.
    static func prosodyRate(fromAVRate rate: Float) -> String {
        if rate < 0.46 { return "-10%" }
        if rate > 0.53 { return "+10%" }
        return "+0%"
    }

    /// Slight lift for questions / exclamations. Conservative by design:
    /// Xiaoxiao already phrases punctuation (measured: 0.66 s pause after
    /// ?/!, 0.25 s after ,); this only nudges it. Empty string = no change.
    static func prosodyPitch(for sentence: String) -> String {
        if sentence.hasSuffix("?") || sentence.hasSuffix("？") { return "+2Hz" }
        return "+0Hz"
    }

    /// SSML for one sentence. ONLY voice + prosody: express-as and break
    /// are rejected by this endpoint (see file header). Text is XML-escaped;
    /// bot replies contain Markdown, unescaped text gets the whole request
    /// silently dropped.
    static func ssml(text: String, voice: Voice, rate: String, pitch: String = "+0Hz") -> String {
        "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>"
            + "<voice name='\(voice.rawValue)'>"
            + "<prosody pitch='\(pitch)' rate='\(rate)' volume='+0%'>\(escape(text))</prosody>"
            + "</voice></speak>"
    }

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// JavaScript-style UTC date string, exactly as edge-tts sends it.
    static func dateString(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT+0000 (Coordinated Universal Time)'"
        return formatter.string(from: date)
    }

    /// The `speech.config` message. Must be sent before the SSML.
    static func configMessage() -> String {
        "X-Timestamp:\(dateString())\r\n"
            + "Content-Type:application/json; charset=utf-8\r\n"
            + "Path:speech.config\r\n\r\n"
            + "{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":"
            + "{\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"true\"},"
            + "\"outputFormat\":\"\(outputFormat)\"}}}}\r\n"
    }

    /// The `ssml` message. Note the trailing `Z` after the timestamp: that
    /// is not a typo, it reproduces an Edge quirk (edge-tts comments it as
    /// "Microsoft Edge bug").
    static func ssmlMessage(ssml: String) -> String {
        "X-RequestId:\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())\r\n"
            + "Content-Type:application/ssml+xml\r\n"
            + "X-Timestamp:\(dateString())Z\r\n"
            + "Path:ssml\r\n\r\n"
            + ssml
    }

    /// Extracts the MP3 body from one binary WebSocket frame.
    /// Frame layout: 2 bytes big-endian header length, then headers, then body.
    /// Returns nil when the frame is not an audio frame; empty Data when it is
    /// the stream-terminating audio frame (no Content-Type, no body).
    static func audioBody(from message: Data) -> Data? {
        guard message.count >= 2 else { return nil }
        let headerLength = Int(message[0]) << 8 | Int(message[1])
        guard headerLength + 2 <= message.count else { return nil }
        let header = String(decoding: message[2..<(2 + headerLength)], as: UTF8.self)
        guard header.contains("Path:audio") else { return nil }
        return Data(message[(2 + headerLength)...])
    }

    // MARK: - Errors

    enum Error: Swift.Error, LocalizedError {
        /// Handshake rejected (e.g. 403: Sec-MS-GEC wrong or expired algorithm).
        case handshakeFailed(statusCode: Int?)
        /// The connection closed before any audio arrived. This is also what
        /// unsupported SSML (express-as / break) looks like: turn.start, then
        /// silence. Never treat it as "finished reading".
        case noAudio
        /// The server sent an explicit error frame.
        case serverError(String)
        case timeout
        case network(Swift.Error)

        var errorDescription: String? {
            // Literals, not L(): these errors are never shown to the user —
            // VoiceStore skips a failed sentence silently — so they must not
            // add L10n keys.
            switch self {
            case .handshakeFailed(let code):
                return "语音服务握手失败\(code.map { "（\($0)）" } ?? "")。"
            case .noAudio:
                return "语音服务没有返回音频。"
            case .serverError(let message):
                return "语音服务出错：\(message)"
            case .timeout:
                return "语音服务超时。"
            case .network(let error):
                return error.localizedDescription
            }
        }
    }

    // MARK: - Synthesizer (one WebSocket connection per sentence)

    struct Synthesizer {
        /// Synthesizes one sentence to MP3 data. Opens a fresh connection
        /// per sentence (the service is stateless per request; reusing a
        /// connection across sentences is a v2 optimisation, not v1).
        func synthesize(text: String, voice: Voice, avRate: Float) async throws -> Data {
            try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask {
                    try await self.synthesizeOnce(
                        text: text,
                        voice: voice,
                        rate: EdgeTTS.prosodyRate(fromAVRate: avRate),
                        pitch: EdgeTTS.prosodyPitch(for: text)
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(EdgeTTS.wholeSentenceTimeout * 1_000_000_000))
                    throw EdgeTTS.Error.timeout
                }
                guard let data = try await group.next() else { throw EdgeTTS.Error.noAudio }
                group.cancelAll()
                return data
            }
        }

        private func synthesizeOnce(text: String, voice: Voice, rate: String, pitch: String) async throws -> Data {
            let connectionId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            var components = URLComponents(string: EdgeTTS.wssBaseURL)!
            components.queryItems = [
                URLQueryItem(name: "TrustedClientToken", value: EdgeTTS.trustedClientToken),
                URLQueryItem(name: "ConnectionId", value: connectionId),
                URLQueryItem(name: "Sec-MS-GEC", value: EdgeDRM.generateSecMsGec()),
                URLQueryItem(name: "Sec-MS-GEC-Version", value: EdgeTTS.secMsGecVersion),
            ]
            var request = URLRequest(url: components.url!)
            request.setValue(EdgeTTS.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(EdgeTTS.origin, forHTTPHeaderField: "Origin")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            request.setValue("muid=\(EdgeDRM.generateMuid());", forHTTPHeaderField: "Cookie")

            let task = URLSession.shared.webSocketTask(with: request)
            task.resume()
            var audio = Data()
            do {
                try await task.send(.string(EdgeTTS.configMessage()))
                try await task.send(.string(EdgeTTS.ssmlMessage(
                    ssml: EdgeTTS.ssml(text: text, voice: voice, rate: rate, pitch: pitch)
                )))
                while true {
                    switch try await task.receive() {
                    case .string(let frame):
                        if frame.contains("Path:turn.end") {
                            task.cancel(with: .normalClosure, reason: nil)
                            guard !audio.isEmpty else { throw EdgeTTS.Error.noAudio }
                            return audio
                        }
                        if frame.contains("Path:error") {
                            throw EdgeTTS.Error.serverError(String(frame.prefix(300)))
                        }
                    case .data(let frame):
                        if let body = EdgeTTS.audioBody(from: frame), !body.isEmpty {
                            audio.append(body)
                        }
                    @unknown default:
                        break
                    }
                }
            } catch {
                task.cancel(with: .goingAway, reason: nil)
                // The server sometimes closes right after the last audio
                // chunk without turn.end; partial audio is still playable.
                if !audio.isEmpty { return audio }
                if let edgeError = error as? EdgeTTS.Error { throw edgeError }
                throw EdgeTTS.Error.network(error)
            }
        }
    }
}

// MARK: - Sec-MS-GEC (client-side token, ported from edge-tts drm.py)
//
// Transliteration notes (read before touching this code):
// - This is NOT standard SHA-256: the initial state is seeded from the
//   first 7 bytes of the input, the schedule/round constants are adjusted,
//   and the digest is then mixed through CS64. CryptoKit cannot substitute.
// - All arithmetic is mod 2^32. Python ints are unbounded, but every value
//   in drm.py is masked to 32 bits before it is used, so Swift `&+` / `&*`
//   (wrapping) reproduces it exactly. The two places Python lets a value
//   grow unmasked (`swap_acc += ...`, `acc += state`) are masked later in
//   the same loop iteration before any read, so wrapping early is equivalent.
// - `_sha256_rounds` in drm.py is an 8-at-a-time unrolled optimisation of
//   the standard 64-round loop (rotated registers). The loop below is the
//   plain per-round form with identical t1/t2/Ch/Maj formulas.
// - The round function picks BLOCK constants when firstRound == 14, ROUND
//   constants otherwise (drm.py chooses once, before the loop).
// - UNVERIFIED: this VM has no Xcode/Swift toolchain. The unit-test vectors
//   at the end of this file MUST pass on the Mac before any network test.
enum EdgeDRM {

    /// Windows epoch offset (seconds between 1601-01-01 and 1970-01-01).
    static let windowsEpoch: TimeInterval = 11644473600

    /// `Sec-MS-GEC` for now (or for a fixed timestamp in tests). The token
    /// changes every 300 seconds; the server rounds the same way.
    static func generateSecMsGec(unixTimestamp: TimeInterval? = nil) -> String {
        var ticks = (unixTimestamp ?? Date().timeIntervalSince1970) + windowsEpoch
        ticks -= ticks.truncatingRemainder(dividingBy: 300)
        ticks *= 1e7 // S_TO_NS / 100: seconds -> 100-nanosecond ticks
        let input = String(format: "%.0f", ticks) + EdgeTTS.trustedClientToken
        let (cs64, sha256) = tokenHash(data: Data(input.utf8))
        return "\(cs64)-\(sha256)"
    }

    /// 32 uppercase hex chars (16 random bytes), for the `muid` cookie.
    static func generateMuid() -> String {
        (0..<16).map { _ in String(format: "%02X", UInt8.random(in: 0...255)) }.joined()
    }

    // MARK: - Token hash

    static func tokenHash(data: Data) -> (cs64: String, sha256: String) {
        let digest = sha256Digest(data: data)
        let (w0, w1) = cs64Digest(data: data, digest: digest)
        var littleEndian = Data()
        for word in [w0, w1] {
            var value = word.littleEndian
            littleEndian.append(contentsOf: withUnsafeBytes(of: &value) { Array($0) })
        }
        return (
            littleEndian.map { String(format: "%02X", $0) }.joined(),
            digest.map { String(format: "%02X", $0) }.joined()
        )
    }

    // MARK: - Custom SHA-256 variant

    static func rol16(_ value: UInt32) -> UInt32 {
        (value << 16) | (value >> 16)
    }

    /// SHA-256 small sigma 0 (as written in drm.py: shifts, masked at use).
    static func smallSigma0(_ value: UInt32) -> UInt32 {
        (value >> 7) ^ (value << 25) ^ (value >> 18) ^ (value << 14) ^ (value >> 3)
    }

    /// SHA-256 small sigma 1 (as written in drm.py).
    static func smallSigma1(_ value: UInt32) -> UInt32 {
        (value >> 17) ^ (value << 15) ^ (value >> 19) ^ (value << 13) ^ (value >> 10)
    }

    static func rotr32(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value >> count) | (value << (32 - count))
    }

    static func sha256Rounds(state: [UInt32], words: [UInt32], firstRound: Int) -> [UInt32] {
        var (a, b, c, d, e, f, g, h) = (state[0], state[1], state[2], state[3], state[4], state[5], state[6], state[7])
        let constants = firstRound == 14 ? EdgeTTS.sha256BlockConstants : EdgeTTS.sha256RoundConstants
        for index in firstRound..<64 {
            let s1 = rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25)
            let ch = g ^ (e & (f ^ g))
            let t1 = h &+ s1 &+ ch &+ constants[index] &+ words[index]
            let s0 = rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22)
            let maj = (a & b) | (c & (a | b))
            let t2 = s0 &+ maj
            h = g
            g = f
            f = e
            e = d &+ t1
            d = c
            c = b
            b = a
            a = t1 &+ t2
        }
        return [a, b, c, d, e, f, g, h]
    }

    static func expandSchedule(_ words: inout [UInt32], firstWord: Int = 16) {
        for index in firstWord..<64 {
            let sigma1 = smallSigma1(words[index - 2])
            let sigma0 = smallSigma0(words[index - 15])
            words.append(sigma1 &+ words[index - 7] &+ sigma0 &+ words[index - 16])
        }
    }

    /// Initial state for token data. `data` must be exactly the first 7
    /// bytes of the token input. Note words[14] is a THREE-byte big-endian
    /// integer (data[0..<3]), words[15] a four-byte one (data[3..<7]).
    static func sha256Init(data: Data) -> [UInt32] {
        precondition(data.count == 7, "sha256Init takes exactly 7 bytes")
        var words = [UInt32](repeating: 0, count: 14)
        words.append((UInt32(data[0]) << 16) | (UInt32(data[1]) << 8) | UInt32(data[2]))
        words.append(be32(data, offset: 3))
        for index in 16..<30 {
            var value = EdgeTTS.sha256Schedule[index - 16]
            if index - 2 >= 14 {
                value &+= index == 16
                    ? (smallSigma1(words[index - 2]) ^ EdgeTTS.sha256Sigma1Adjustment)
                    : smallSigma1(words[index - 2])
            }
            if index - 7 >= 14 {
                value &+= words[index - 7]
            }
            if index - 15 >= 14 {
                value &+= index == 29
                    ? (smallSigma0(words[index - 15]) ^ EdgeTTS.sha256Sigma0Adjustment)
                    : smallSigma0(words[index - 15])
            }
            words.append(value)
        }
        words.append(
            smallSigma1(words[28]) &+ words[23] &+ smallSigma0(words[15]) &+ words[14]
                &+ EdgeTTS.sha256Adjustment &- EdgeTTS.sha256RoundConstants[14]
        )
        expandSchedule(&words, firstWord: 31)
        let working = sha256Rounds(state: EdgeTTS.sha256State, words: words, firstRound: 14)
        return zip(EdgeTTS.sha256Initial, working).map { $0 &+ $1 }
    }

    static func sha256Digest(data: Data) -> Data {
        precondition(data.count >= 7, "token input must be at least 7 bytes")
        let length = 57 + data.count
        // Python: (55 - length) % 64 is always non-negative; Swift % is not.
        let padZeros = ((55 - length) % 64 + 64) % 64
        var padded = Data(data.dropFirst(7))
        padded.append(0x80)
        padded.append(contentsOf: [UInt8](repeating: 0, count: padZeros))
        var bitLength = UInt64(length * 8).bigEndian
        padded.append(contentsOf: withUnsafeBytes(of: &bitLength) { Array($0) })

        var state = sha256Init(data: Data(data.prefix(7)))
        for offset in stride(from: 0, to: padded.count, by: 64) {
            var words: [UInt32] = []
            for wordIndex in 0..<16 {
                words.append(be32(padded, offset: offset + wordIndex * 4))
            }
            expandSchedule(&words)
            let working = sha256Rounds(state: state, words: words, firstRound: 0)
            state = zip(state, working).map { $0 &+ $1 }
        }
        var out = Data()
        for word in state {
            var bigEndian = word.bigEndian
            out.append(contentsOf: withUnsafeBytes(of: &bigEndian) { Array($0) })
        }
        return out
    }

    // MARK: - CS64

    /// Splits data into little-endian 32-bit words, zero-padded to an even count.
    /// The input is prefixed with one zero byte by the caller (drm.py).
    static func wordsLE4Even(_ data: Data) -> [UInt32] {
        var bytes = [UInt8](data)
        while bytes.count % 4 != 0 { bytes.append(0) }
        var words: [UInt32] = []
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            words.append(
                UInt32(bytes[offset])
                    | (UInt32(bytes[offset + 1]) << 8)
                    | (UInt32(bytes[offset + 2]) << 16)
                    | (UInt32(bytes[offset + 3]) << 24)
            )
        }
        if words.count % 2 == 1 { words.append(0) }
        return words
    }

    static func cs64Digest(data: Data, digest: Data) -> (UInt32, UInt32) {
        let keyA = le32(digest, offset: 0) | 1
        let keyB = le32(digest, offset: 4) | 1
        let factors = [keyA &* EdgeTTS.cs64Factor, keyB &* EdgeTTS.cs64Factor]
        var terms: [UInt32] = EdgeTTS.cs64Coefficients.enumerated().map { index, pair in
            pair.0 &* factors[index % 2]
        }
        var offsets: [UInt32] = EdgeTTS.cs64Coefficients.map { $0.1 }
        for (index, word) in wordsLE4Even(Data([0]) + data).enumerated() {
            var term = word &* (index % 2 == 0 ? keyA : keyB)
            var offset = rol16(word) &* (index % 2 == 0 ? 0xEF0569FB : 0xC31713DB)
            if index == 0 {
                term &+= EdgeTTS.cs64Adjustment0 &* factors[0]
                offset &+= EdgeTTS.cs64Adjustment1
            }
            terms.append(term)
            offsets.append(offset)
        }
        var swapAcc: UInt32 = 0
        var swapLast: UInt32 = 0
        var state: UInt32 = 0
        var acc: UInt32 = 0
        for index in stride(from: 0, to: terms.count, by: 2) {
            let x = terms[index]
            let y = terms[index + 1]
            var t = rol16(offsets[index] &+ x)
            var q = t &* 0x76F50F34
            swapAcc &+= (rol16(q) &* 0xC3EFEA97 &+ q)
            t = rol16(offsets[index + 1] &+ y)
            q = t &* 0x1881CE3C
            swapLast = (rol16(q) &* 0x35BD1EC9 &+ q)
            swapAcc &+= swapLast

            state = (state &* keyA) &+ x
            state = rol16(state) &* 0xCF98B111
            state = rol16(state) &* 0x87085B9F
            state = rol16(state) &* 0x12CEB96D
            state = rol16(state) &* 0x257E1D83
            acc &+= state
            t = (state &* keyB) &+ y
            t = rol16(t) &* 0xA27416F5
            t = rol16(t) &* 0xD38396FF
            state = rol16(rol16(t) &* 0x7C932B89) &* 0xBFA49F69
            acc &+= state
        }
        return (swapLast ^ state, swapAcc ^ acc)
    }

    // MARK: - Byte helpers

    static func be32(_ data: Data, offset: Int) -> UInt32 {
        (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }

    static func le32(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}

// MARK: - Playback (one sentence of MP3 data)

/// Plays Edge MP3 data and reports completion. The finish callback is the
/// only thing that may advance the speech queue, and it must be delivered
/// on the main actor
/// (the caller wraps it in `Task { @MainActor in ... }`, as VoiceStore does).
final class EdgeTTSPlayer: NSObject, AVAudioPlayerDelegate {

    private var player: AVAudioPlayer?
    private var onFinish: (() -> Void)?

    /// Returns false when the data cannot be played (corrupt/empty).
    @discardableResult
    func play(_ data: Data, onFinish: @escaping () -> Void) -> Bool {
        stop()
        guard !data.isEmpty else { return false }
        do {
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            self.player = player
            self.onFinish = onFinish
            player.prepareToPlay()
            return player.play()
        } catch {
            return false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        onFinish = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let callback = onFinish
        onFinish = nil
        self.player = nil
        callback?()
    }
}

// MARK: - Unit-test vectors (run FIRST, before any network test)
//
// Copy into the app's test target (e.g. `EdgeTTSTests.testSecMsGec`):
//
//   func testSecMsGecVectors() {
//       XCTAssertEqual(
//           EdgeDRM.generateSecMsGec(unixTimestamp: 1764000000.0),
//           "BB2B3ADE6A8DD1F3-B07567543B86F99C3539F563D8D3368C59A22CAF50BF1E35F42DA34792F80A76")
//       XCTAssertEqual(
//           EdgeDRM.generateSecMsGec(unixTimestamp: 1795297000.0),
//           "CA77E46AC1D8DD7A-42207798DFE31F959507C618E638D1D7297E8BA5A48021BBC6D1E4BCA9A44383")
//       XCTAssertEqual(
//           EdgeDRM.generateSecMsGec(unixTimestamp: 0.0),
//           "52BC7A17B50DFEC9-28C4394775C8751CD2F6859C030C06DB1489ACAB3B3A7651831FC26895177ED6")
//   }
//
//   func testMuidShape() {
//       let muid = EdgeDRM.generateMuid()
//       XCTAssertEqual(muid.count, 32)
//       XCTAssertEqual(muid, muid.uppercased())
//       XCTAssertTrue(muid.allSatisfy { $0.isHexDigit })
//   }
//
//   func testSsmlShape() {
//       let ssml = EdgeTTS.ssml(text: "你好呀！", voice: .xiaoxiao, rate: "+0%")
//       XCTAssertTrue(ssml.contains("zh-CN-XiaoxiaoNeural"))
//       XCTAssertFalse(ssml.contains("express-as"))
//       XCTAssertFalse(ssml.contains("break"))
//   }
//
// Vectors generated 2026-11-22 from edge-tts 7.3.1 `drm.generate_sec_ms_gec_v2`.
// If any vector fails, the DRM port is wrong: do NOT build, do NOT test the
// network path, fix the port first. A single wrong constant bit gives 403.
