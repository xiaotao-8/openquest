import Foundation
import Network

/// DNS 设置（用户在设置里选）：跟随系统（默认关）/ 阿里 / 腾讯 / 114 / 自定义。
/// 真生效的方式：App 自己的网络请求（模型、服务器、抓网页、拉模型）都走
/// Net.session；开启后请求先用所选 DNS 服务器（UDP 53）把域名解析成 IP，
/// 再按 IP 直连、证书按原域名校验——不是摆设开关。
/// 解析失败一律回退系统解析，绝不因为 DNS 设置把聊天弄断。
enum DNSSettings {
    static var mode: String {
        get { UserDefaults.standard.string(forKey: "oq.dns.mode") ?? "system" }
        set { UserDefaults.standard.set(newValue, forKey: "oq.dns.mode") }
    }
    static var custom: String {
        get { UserDefaults.standard.string(forKey: "oq.dns.custom") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "oq.dns.custom") }
    }
    /// 当前生效的 DNS 服务器 IP；跟随系统时为 nil。
    static var serverIP: String? {
        switch mode {
        case "ali": return "223.5.5.5"
        case "tencent": return "119.29.29.29"
        case "114": return "114.114.114.114"
        case "custom":
            let c = custom.trimmingCharacters(in: .whitespaces)
            return c.isEmpty ? nil : c
        default: return nil
        }
    }
    static var enabled: Bool { serverIP != nil }
}

/// 极简 DNS 解析器：向指定服务器发一条 UDP A 记录查询，取第一个 IPv4。
/// 带 5 分钟缓存；超时 1.5 秒，失败返回 nil（调用方回退系统解析）。
enum DNSResolver {
    private static var cache: [String: (ip: String, at: Date)] = [:]
    private static let lock = NSLock()

    static func resolve(host: String, server: String) async -> String? {
        lock.lock()
        if let hit = cache[host], Date().timeIntervalSince(hit.at) < 300 {
            lock.unlock()
            return hit.ip
        }
        lock.unlock()
        guard let ip = await query(host: host, server: server) else { return nil }
        lock.lock()
        cache[host] = (ip, Date())
        lock.unlock()
        return ip
    }

    private static func query(host: String, server: String) async -> String? {
        let conn = NWConnection(host: NWEndpoint.Host(server), port: 53, using: .udp)
        let packet = buildQuery(host: host)
        return await withCheckedContinuation { cont in
            let box = ResumeBox()
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.send(content: packet, completion: .contentProcessed { _ in })
                    conn.receiveMessage { data, _, _, _ in
                        if box.claim() {
                            cont.resume(returning: data.flatMap { parseAnswer($0) })
                        }
                        conn.cancel()
                    }
                case .failed, .cancelled:
                    if box.claim() { cont.resume(returning: nil) }
                default: break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                if box.claim() { cont.resume(returning: nil) }
                conn.cancel()
            }
        }
    }

    private final class ResumeBox {
        private var done = false
        private let l = NSLock()
        func claim() -> Bool { l.lock(); defer { l.unlock() }; if done { return false }; done = true; return true }
    }

    private static func buildQuery(host: String) -> Data {
        var d = Data()
        let txid = UInt16.random(in: 0...UInt16.max)
        d.append(UInt8(txid >> 8)); d.append(UInt8(txid & 0xff))
        d.append(contentsOf: [0x01, 0x00])          // RD
        d.append(contentsOf: [0x00, 0x01])          // QDCOUNT 1
        d.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        for label in host.split(separator: ".") {
            let bytes = Array(label.utf8)
            d.append(UInt8(bytes.count))
            d.append(contentsOf: bytes)
        }
        d.append(0)
        d.append(contentsOf: [0x00, 0x01])          // A
        d.append(contentsOf: [0x00, 0x01])          // IN
        return d
    }

    private static func parseAnswer(_ data: Data) -> String? {
        let b = [UInt8](data)
        guard b.count > 12 else { return nil }
        let qd = Int(b[4]) << 8 | Int(b[5])
        let an = Int(b[6]) << 8 | Int(b[7])
        guard an > 0 else { return nil }
        var off = 12
        func skipName() {
            while off < b.count {
                let len = Int(b[off]); off += 1
                if len == 0 { break }
                if len & 0xC0 == 0xC0 { off += 1; break }
                off += len
            }
        }
        for _ in 0..<qd { skipName(); off += 4 }
        for _ in 0..<an {
            skipName()
            guard off + 10 <= b.count else { return nil }
            let type = Int(b[off]) << 8 | Int(b[off + 1])
            let rdlen = Int(b[off + 8]) << 8 | Int(b[off + 9])
            off += 10
            if type == 1 && rdlen == 4 && off + 4 <= b.count {
                return "\(b[off]).\(b[off + 1]).\(b[off + 2]).\(b[off + 3])"
            }
            off += rdlen
        }
        return nil
    }
}

/// 把请求按所选 DNS 的解析结果直连 IP 的 URLProtocol。
/// HTTPS 时证书按原域名校验（SecPolicy 绑原域名），不是无脑信任。
final class DNSProtocol: URLProtocol {
    private var inner: URLSessionDataTask?
    private var session: URLSession?
    private static let handledKey = "oq.dns.handled"
    private static let hostKey = "oq.dns.host"

    override class func canInit(with request: URLRequest) -> Bool {
        guard DNSSettings.enabled,
              let url = request.url,
              let scheme = url.scheme, scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty,
              URLProtocol.property(forKey: handledKey, in: request) == nil
        else { return false }
        // 已经是 IP 或本机名，不折腾。
        if host == "localhost" || host.allSatisfy({ $0.isNumber || $0 == "." || $0 == ":" }) {
            return false
        }
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host, let server = DNSSettings.serverIP else {
            loadOriginal(request)
            return
        }
        let original = request
        Task {
            let ip = await DNSResolver.resolve(host: host, server: server)
            guard let ip else {
                self.loadOriginal(original)
                return
            }
            var comps = URLComponents(url: original.url!, resolvingAgainstBaseURL: false)
            comps?.host = ip
            guard let newURL = comps?.url else { self.loadOriginal(original); return }
            let mreq = (original as NSURLRequest).mutableCopy() as! NSMutableURLRequest
            mreq.url = newURL
            mreq.setValue(host, forHTTPHeaderField: "Host")
            URLProtocol.setProperty(true, forKey: Self.handledKey, in: mreq)
            URLProtocol.setProperty(host, forKey: Self.hostKey, in: mreq)
            self.load(mreq as URLRequest, originalHost: host)
        }
    }

    override func stopLoading() {
        inner?.cancel()
        session?.invalidateAndCancel()
    }

    private func loadOriginal(_ req: URLRequest) {
        load(req, originalHost: req.url?.host ?? "")
    }

    private func load(_ req: URLRequest, originalHost: String) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = []
        let s = URLSession(configuration: config, delegate: CertDelegate(host: originalHost, owner: self), delegateQueue: nil)
        session = s
        let task = s.dataTask(with: req)
        inner = task
        task.resume()
    }

    fileprivate func didReceive(_ data: Data) { client?.urlProtocol(self, didLoad: data) }
    fileprivate func didReceive(_ response: URLResponse) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }
    fileprivate func didFinish() { client?.urlProtocolDidFinishLoading(self) }
    fileprivate func didFail(_ error: Error) { client?.urlProtocol(self, didFailWithError: error) }
}

/// 内层会话的代理：把数据转给 URLProtocol 的 client；证书按原域名校验。
private final class CertDelegate: NSObject, URLSessionDataDelegate {
    let host: String
    weak var owner: DNSProtocol?
    init(host: String, owner: DNSProtocol) { self.host = host; self.owner = owner }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        owner?.didReceive(data)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        owner?.didReceive(response)
        return .allow
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { owner?.didFail(error) } else { owner?.didFinish() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }
        // 按原域名校验这张证书：策略绑原域名，系统验链，过了才用。
        let policy = SecPolicyCreateSSL(true, host as CFString)
        SecTrustSetPolicies(trust, policy)
        var err: CFError?
        if SecTrustEvaluateWithError(trust, &err) {
            return (.useCredential, URLCredential(trust: trust))
        }
        return (.cancelAuthenticationChallenge, nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        // 不跟随跳转：把 3xx 响应本身当最终响应交给 client，避免循环。
        return nil
    }
}

/// App 统一网络出口：DNS 开着就带 DNSProtocol，没开就是普通会话。
/// 会话按当前 DNS 设置缓存复用，设置变了才重建。
enum Net {
    private static var cached: URLSession?
    private static var cachedKey = ""
    static var session: URLSession {
        guard DNSSettings.enabled else { return .shared }
        let key = DNSSettings.mode + "|" + DNSSettings.custom
        if let c = cached, cachedKey == key { return c }
        let config = URLSessionConfiguration.default
        config.protocolClasses = [DNSProtocol.self]
        let s = URLSession(configuration: config)
        cached = s
        cachedKey = key
        return s
    }
}
