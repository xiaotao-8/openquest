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

    /// 流式回复：模型吐字就回调 onDelta（正文累计、思考累计），界面边收边显示。
    /// 工具调用也在流里拼出来，拼完照常执行/转卡片，之后继续流式。
    func reply(agent: Agent, history: [(role: String, content: String)],
               imageJPEG: Data? = nil,
               skillsContext: String = "",
               onToolEvent: ((String, Data?) -> Void)? = nil,
               onDelta: @escaping (String, String) -> Void) async throws -> TurnResult {
        guard let key = KeychainHelper.key(ref: provider.keyRef), !key.isEmpty else {
            throw RunnerError.noKey
        }
        let url = URL(string: provider.baseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions")!
        var messages: [[String: Any]] = []
        // 内置人设是基础层：每个智能体、每次调用都带，在自设人设之下。
        // 层级：用户自设人设（Soul）置顶最高优先，其下是写死的内置人设基础层。
        var system = ""
        if !agent.soul.isEmpty {
            system = agent.soul
                + "\n\n【执行要求】以上人设与规则是最高优先级，必须严格照做：始终按设定的人设、身份、语气和规矩行事；用户的问题要直接回答，不无故拒绝、不逃避、不绕开话题；交给你的任务要实际执行——该调用工具就调用工具真干，不许拒绝执行，也不许只给建议、只说方法不干活。"
            system += "\n\n" + BakedPersona.text
        } else {
            system = BakedPersona.text
        }
        if !skillsContext.isEmpty {
            system += (system.isEmpty ? "" : "\n\n") + skillsContext
        }
        if !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }
        for h in history {
            messages.append(["role": h.role, "content": h.content])
        }
        // 底层逻辑：在对话末尾再钉一条系统提醒（多数模型最听最后一条），
        // 保证不是只在开头说说而已——每轮都强制带上，关不掉。
        messages.append(["role": "system",
                         "content": "【底层规则】始终按你的人设行事；直接回答用户的问题，不无故拒绝、不逃避、不绕开话题；任务要真执行，不许拒绝执行、不许只给建议不干活。"])
        // 图片挂在最后一条用户消息上（视觉模型的多模态格式）。
        if let imageJPEG,
           let idx = messages.lastIndex(where: { ($0["role"] as? String) == "user" }) {
            let text = messages[idx]["content"] as? String ?? ""
            messages[idx]["content"] = [
                ["type": "text", "text": text],
                ["type": "image_url",
                 "image_url": ["url": "data:image/jpeg;base64,\(imageJPEG.base64EncodedString())"]],
            ]
        }

        var reasoningAll = ""
        var contentAll = ""
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
                "stream": true,
            ])
            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { throw RunnerError.badStatus(code) }

            // 拼流式分片：正文、思考、工具调用（按 index 分片拼参数）。
            var toolCalls: [Int: (id: String, name: String, args: String)] = [:]
            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { break }
                guard let data = payload.data(using: .utf8),
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let delta = (root["choices"] as? [[String: Any]])?.first?["delta"] as? [String: Any]
                else { continue }
                if let c = delta["content"] as? String { contentAll += c }
                if let r = delta["reasoning_content"] as? String { reasoningAll += r }
                if let r = delta["reasoning"] as? String { reasoningAll += r }
                if let calls = delta["tool_calls"] as? [[String: Any]] {
                    for call in calls {
                        let idx = call["index"] as? Int ?? 0
                        var cur = toolCalls[idx] ?? (id: "", name: "", args: "")
                        if let id = call["id"] as? String { cur.id = id }
                        if let fn = call["function"] as? [String: Any] {
                            if let n = fn["name"] as? String { cur.name += n }
                            if let a = fn["arguments"] as? String { cur.args += a }
                        }
                        toolCalls[idx] = cur
                    }
                }
                onDelta(contentAll, reasoningAll)
            }

            if !toolCalls.isEmpty {
                let ordered = toolCalls.sorted { $0.key < $1.key }.map { $0.value }
                // 提问卡 / 审批卡要等用户在界面上作答：直接把卡片交出去，本轮结束。
                for call in ordered {
                    if call.name == AgentTools.askUserName, let card = Self.askCard(from: call.args) {
                        return .card(card)
                    }
                    if call.name == AgentTools.approvalName, let card = Self.approvalCard(from: call.args) {
                        return .card(card)
                    }
                }
                messages.append([
                    "role": "assistant",
                    "content": contentAll,
                    "tool_calls": ordered.map { call in
                        ["id": call.id, "type": "function",
                         "function": ["name": call.name, "arguments": call.args]] as [String: Any]
                    },
                ])
                for call in ordered {
                    let result = await AgentTools.execute(
                        name: call.name, argumentsJSON: call.args,
                        agentId: agent.id.uuidString, server: server,
                        onEvent: onToolEvent)
                    messages.append([
                        "role": "tool",
                        "tool_call_id": call.id,
                        "content": result,
                    ])
                }
                contentAll = ""
                continue
            }
            let finalText = contentAll.trimmingCharacters(in: .whitespacesAndNewlines)
            return .text(finalText, reasoning: reasoningAll.isEmpty ? nil : reasoningAll)
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
