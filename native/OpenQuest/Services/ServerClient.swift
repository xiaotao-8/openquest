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
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "agentId": agentId,
            "command": command,
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
}
