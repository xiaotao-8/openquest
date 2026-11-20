import Foundation

/// 调用用户自己的服务器（ECS 上的智能体宿主服务，令牌鉴权）。
/// 智能体干活时通过它在服务器上执行命令、用服务器的终端和工作区。
struct ServerClient {
    let config: ServerConfig

    /// 令牌：优先用打包时内置的那份（用户不用配），没有再读钥匙串。
    private var token: String? {
        if !BakedServer.token.isEmpty { return BakedServer.token }
        return KeychainHelper.key(ref: config.tokenRef)
    }

    struct ExecResult: Decodable {
        var stdout: String = ""
        var stderr: String = ""
        var exitCode: Int = 0
        // 服务器回的是 snake_case：exit_code。
        enum CodingKeys: String, CodingKey { case stdout, stderr, exitCode = "exit_code" }
    }

    enum ClientError: Error, LocalizedError {
        case noToken, badStatus(Int), badResponse
        var errorDescription: String? {
            switch self {
            case .noToken: return "服务器令牌没填"
            case .badStatus(let c): return "服务器返回 \(c)"
            case .badResponse: return "服务器响应看不懂"
            }
        }
    }

    /// 在服务器上以某个智能体的身份执行一条命令（在它自己的工作目录里）。
    func exec(agentId: String, command: String) async throws -> ExecResult {
        guard let token, !token.isEmpty else {
            throw ClientError.noToken
        }
        guard let url = URL(string: config.baseURL + "/exec") else {
            throw ClientError.badResponse
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 服务器契约（/opt/openquest/server/server.py 的 _exec）：{"bot", "cmd"}。
        // 之前这里发的是 {"agentId", "command"}，服务器会 400（invalid bot name）。
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "bot": agentId,
            "cmd": command,
        ])
        let (data, resp) = try await Net.session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ClientError.badStatus(code) }
        return try JSONDecoder().decode(ExecResult.self, from: data)
    }

    struct BrowseResult: Decodable {
        var title: String = ""
        var text: String = ""
        var screenshotBase64: String? = nil   // 服务器浏览器的截图（PNG），App 显示这个
    }

    struct BrowserState: Decodable {
        var title: String = ""
        var url: String = ""
        var text: String = ""
        var screenshotBase64: String? = nil
    }

    /// 服务器浏览器的一步操作——规格跟 Muse 自己的浏览器一样：
    /// 打开、点击、输入、滚动、截图、读正文，智能体一步步驱动；
    /// 浏览器资料（登录状态）在服务器上按智能体持久保存。
    /// action 例：["type":"navigate","url":"https://…"]、["type":"click","x":0.5,"y":0.4]、
    /// ["type":"type","text":"…"]、["type":"scroll","dy":600]、["type":"read"]、["type":"screenshot"]
    func browserAction(agentId: String, action: [String: Any]) async throws -> BrowserState {
        guard let token, !token.isEmpty else {
            throw ClientError.noToken
        }
        guard let endpoint = URL(string: config.baseURL + "/browser") else {
            throw ClientError.badResponse
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "agentId": agentId,
            "action": action,
        ])
        let (data, resp) = try await Net.session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ClientError.badStatus(code) }
        return try JSONDecoder().decode(BrowserState.self, from: data)
    }

    /// 用服务器上的浏览器打开网页，返回标题+正文。
    /// 智能体上网一律走服务器的浏览器——手机只是窗口，真正的电脑在服务器上。
    func browse(agentId: String, url: String) async throws -> BrowseResult {
        guard let token, !token.isEmpty else {
            throw ClientError.noToken
        }
        guard let endpoint = URL(string: config.baseURL + "/browse") else {
            throw ClientError.badResponse
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "agentId": agentId,
            "url": url,
        ])
        let (data, resp) = try await Net.session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ClientError.badStatus(code) }
        return try JSONDecoder().decode(BrowseResult.self, from: data)
    }

    // MARK: 云电脑页用的接口

    struct HealthResult: Decodable {
        var status: String = ""
        var version: String = ""
        var uptime_s: Int = 0
        var bots: [String] = []
        var mem_available_mb: Int? = nil
        var disk_free_gb: Double? = nil
    }

    /// 云电脑是否在线（GET /health；服务器所有接口都要令牌，没令牌直接报没填）。
    func health() async throws -> HealthResult {
        guard let token, !token.isEmpty else {
            throw ClientError.noToken
        }
        guard let url = URL(string: config.baseURL + "/health") else {
            throw ClientError.badResponse
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await Net.session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ClientError.badStatus(code) }
        return try JSONDecoder().decode(HealthResult.self, from: data)
    }

    struct FileEntry: Decodable, Identifiable {
        var name: String
        var dir: Bool = false
        var size: Int? = nil
        var id: String { name }
    }

    private struct FilesListResult: Decodable {
        var entries: [FileEntry] = []
    }

    private struct FilesReadResult: Decodable {
        var content_b64: String = ""
        var size: Int = 0
    }

    /// 列服务器工作区里的文件（GET /files/list?bot=&area=workspace&path=）。
    func filesList(bot: String, path: String = "") async throws -> [FileEntry] {
        guard let token, !token.isEmpty else {
            throw ClientError.noToken
        }
        var comps = URLComponents(string: config.baseURL + "/files/list")
        comps?.queryItems = [
            URLQueryItem(name: "bot", value: bot),
            URLQueryItem(name: "area", value: "workspace"),
            URLQueryItem(name: "path", value: path),
        ]
        guard let url = comps?.url else { throw ClientError.badResponse }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await Net.session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ClientError.badStatus(code) }
        return try JSONDecoder().decode(FilesListResult.self, from: data).entries
    }

    /// 读服务器工作区里的一个文件（GET /files/read，内容是 base64）。
    func filesRead(bot: String, path: String) async throws -> String {
        guard let token, !token.isEmpty else {
            throw ClientError.noToken
        }
        var comps = URLComponents(string: config.baseURL + "/files/read")
        comps?.queryItems = [
            URLQueryItem(name: "bot", value: bot),
            URLQueryItem(name: "area", value: "workspace"),
            URLQueryItem(name: "path", value: path),
        ]
        guard let url = comps?.url else { throw ClientError.badResponse }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await Net.session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ClientError.badStatus(code) }
        let result = try JSONDecoder().decode(FilesReadResult.self, from: data)
        guard let bytes = Data(base64Encoded: result.content_b64),
              let text = String(data: bytes, encoding: .utf8) else {
            return "（不是文本文件，看不了内容）"
        }
        return text
    }
}
