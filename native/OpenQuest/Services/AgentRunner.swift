import Foundation

/// 让一个智能体回复一轮：把人设（Soul）作最高优先级系统指令，
/// 带上会话历史请求模型；模型要调工具（服务器命令等）就执行后把结果回给它，
/// 循环到它给出最终回复。任何 OpenAI 兼容供应商都走这一套。
struct AgentRunner {
    let provider: ModelProvider
    let server: ServerConfig

    enum RunnerError: Error, LocalizedError {
        case noKey, badStatus(Int), badResponse
        var errorDescription: String? {
            switch self {
            case .noKey: return "供应商的 Key 没填"
            case .badStatus(let c): return "模型服务返回 \(c)"
            case .badResponse: return "模型响应看不懂"
            }
        }
    }

    /// 一轮的结果：要么是文本回复（可带深度思考过程），要么是等用户作答的卡片。
    enum TurnResult {
        case text(String, reasoning: String?)
        case card(CardPayload)
    }

    func reply(agent: Agent, history: [(role: String, content: String)]) async throws -> TurnResult {
        guard let key = KeychainHelper.key(ref: provider.keyRef), !key.isEmpty else {
            throw RunnerError.noKey
        }
        let url = URL(string: provider.baseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions")!
        var messages: [[String: Any]] = []
        if !agent.soul.isEmpty {
            messages.append(["role": "system", "content": agent.soul])
        }
        for h in history {
            messages.append(["role": h.role, "content": h.content])
        }

        var reasoningAll = ""
        for _ in 0..<6 {  // 最多 6 轮工具调用，防死循环乱调
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 120
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": agent.modelId,
                "messages": messages,
                "tools": AgentTools.definitions,
            ])
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { throw RunnerError.badStatus(code) }
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = root["choices"] as? [[String: Any]],
                  let msg = choices.first?["message"] as? [String: Any]
            else { throw RunnerError.badResponse }
            if let r = msg["reasoning_content"] as? String, !r.isEmpty {
                reasoningAll += r
            }

            if let calls = msg["tool_calls"] as? [[String: Any]], !calls.isEmpty {
                // 提问卡 / 审批卡要等用户在界面上作答：直接把卡片交出去，本轮结束。
                for call in calls {
                    let fn = call["function"] as? [String: Any]
                    let name = fn?["name"] as? String ?? ""
                    let args = fn?["arguments"] as? String ?? "{}"
                    if name == AgentTools.askUserName, let card = Self.askCard(from: args) {
                        return .card(card)
                    }
                    if name == AgentTools.approvalName, let card = Self.approvalCard(from: args) {
                        return .card(card)
                    }
                }
                messages.append(msg)
                for call in calls {
                    let fn = call["function"] as? [String: Any]
                    let name = fn?["name"] as? String ?? ""
                    let args = fn?["arguments"] as? String ?? "{}"
                    let result = await AgentTools.execute(
                        name: name, argumentsJSON: args,
                        agentId: agent.id.uuidString, server: server)
                    messages.append([
                        "role": "tool",
                        "tool_call_id": call["id"] as? String ?? "",
                        "content": result,
                    ])
                }
                continue
            }
            return .text((msg["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                         reasoning: reasoningAll.isEmpty ? nil : reasoningAll)
        }
        return .text("（工具调用轮数用完了，先停一下）", reasoning: nil)
    }

    private static func parseArgs(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func askCard(from args: String) -> CardPayload? {
        guard let obj = parseArgs(args),
              let q = obj["question"] as? String,
              let raw = obj["options"] as? [[String: Any]]
        else { return nil }
        let options = raw.compactMap { o -> CardOption? in
            guard let label = o["label"] as? String else { return nil }
            return CardOption(id: (o["id"] as? String) ?? label,
                              label: label,
                              detail: (o["detail"] as? String) ?? "")
        }
        guard !options.isEmpty else { return nil }
        return CardPayload(kind: .ask, question: q, options: options,
                           multiSelect: (obj["multiSelect"] as? Bool) ?? false)
    }

    private static func approvalCard(from args: String) -> CardPayload? {
        guard let obj = parseArgs(args), let action = obj["action"] as? String else { return nil }
        let impact = (obj["impact"] as? String) ?? ""
        return CardPayload(
            kind: .approval,
            question: action,
            options: [
                CardOption(id: "approve", label: "批准", detail: impact),
                CardOption(id: "reject", label: "拒绝", detail: "不执行这个操作"),
            ])
    }
}
