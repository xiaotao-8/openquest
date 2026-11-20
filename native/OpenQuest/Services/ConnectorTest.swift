import Foundation

/// 连接器连通测试：每连接器填 Key/Token 后点“测试”，走一次真实调用，
/// 通过才算连上。只做国内服务 + 自定义 MCP。
enum ConnectorTest {
    /// credential 格式：飞书/钉钉是 "id:secret"；其余直接贴 token/key。
    static func test(id: String, credential: String) async -> String {
        let cred = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cred.isEmpty else { return "先填 Key 或 Token" }
        switch id {
        case "feishu":
            let parts = cred.split { $0 == ":" || $0 == " " || $0 == "\n" }.map(String.init)
            guard parts.count >= 2 else { return "格式：App ID:App Secret（冒号隔开）" }
            return await postJSON(
                url: "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal",
                headers: ["Content-Type": "application/json"],
                body: ["app_id": parts[0], "app_secret": parts[1]],
                ok: { root in (root["code"] as? Int) == 0 },
                okText: "连上了：拿到飞书 tenant_access_token",
                failText: "飞书没连上：App ID 或 Secret 不对")
        case "dingtalk":
            let parts = cred.split { $0 == ":" || $0 == " " || $0 == "\n" }.map(String.init)
            guard parts.count >= 2 else { return "格式：AppKey:AppSecret（冒号隔开）" }
            return await getJSON(
                url: "https://oapi.dingtalk.com/gettoken?appkey=\(parts[0])&appsecret=\(parts[1])",
                headers: [:],
                ok: { root in (root["errcode"] as? Int) == 0 },
                okText: "连上了：拿到钉钉 access_token",
                failText: "钉钉没连上：AppKey 或 Secret 不对")
        case "yuque":
            return await getJSON(
                url: "https://www.yuque.com/api/v2/user",
                headers: ["X-Auth-Token": cred],
                ok: { root in (root["data"] as? [String: Any])?["id"] != nil },
                okText: "连上了：语雀账号已验证",
                failText: "语雀没连上：Token 不对")
        case "gitee":
            return await getJSON(
                url: "https://gitee.com/api/v5/user?access_token=\(cred)",
                headers: [:],
                ok: { root in root["login"] != nil },
                okText: "连上了：Gitee 账号已验证",
                failText: "Gitee 没连上：Token 不对")
        case "bocha":
            return await postJSON(
                url: "https://api.bochaai.com/v1/web-search",
                headers: ["Authorization": "Bearer \(cred)", "Content-Type": "application/json"],
                body: ["query": "测试", "count": 1],
                ok: { root in (root["code"] as? Int) == 200 },
                okText: "连上了：博查搜索可用",
                failText: "博查没连上：Key 不对")
        default:
            return "这个连接器还没接测试"
        }
    }

    /// 自定义 MCP：发一次 JSON-RPC initialize，有 result 回来才算通。
    static func testMCP(url urlString: String) async -> String {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)),
              url.scheme == "https" else {
            return "地址不对：要一个 HTTPS 地址"
        }
        return await postJSON(
            url: urlString,
            headers: ["Content-Type": "application/json"],
            body: ["jsonrpc": "2.0", "id": 1, "method": "initialize",
                   "params": ["protocolVersion": "2024-11-05", "capabilities": [:],
                              "clientInfo": ["name": "OpenQuest", "version": "1"]]] as [String: Any],
            ok: { root in root["result"] != nil },
            okText: "连上了：MCP 服务器有回应",
            failText: "没连上：对方没按 MCP 协议回 initialize")
    }

    private static func getJSON(url urlString: String, headers: [String: String],
                                ok: @escaping ([String: Any]) -> Bool,
                                okText: String, failText: String) async -> String {
        guard let url = URL(string: urlString) else { return "地址不对" }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        do {
            let (data, resp) = try await Net.session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  ok(root)
            else { return failText }
            return okText
        } catch {
            return "网络失败：\(error.localizedDescription)"
        }
    }

    private static func postJSON(url urlString: String, headers: [String: String],
                                 body: [String: Any],
                                 ok: @escaping ([String: Any]) -> Bool,
                                 okText: String, failText: String) async -> String {
        guard let url = URL(string: urlString) else { return "地址不对" }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, resp) = try await Net.session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  ok(root)
            else { return failText }
            return okText
        } catch {
            return "网络失败：\(error.localizedDescription)"
        }
    }
}
