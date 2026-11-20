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
    /// usage 是 SSE usage 段里的输入/输出 token 数（有才填）。
    enum TurnResult {
        case text(String, reasoning: String?, usage: (prompt: Int, completion: Int)? = nil)
        case card(CardPayload)
    }

    /// 流式回复：模型吐字就回调 onDelta（正文累计、思考累计），界面边收边显示。
    /// 工具调用也在流里拼出来，拼完照常执行/转卡片，之后继续流式。
    func reply(agent: Agent, history: [(role: String, content: String)],
               imageJPEG: Data? = nil,
               skillsContext: String = "",
               onToolEvent: ((String, Data?) -> Void)? = nil,
               onSpawnSubagent: ((String, String) async -> String)? = nil,
               capabilities: Set<String> = [],
               webSearch: Bool = false,
               fallbacks: [(provider: ModelProvider, model: AIModel)] = [],
               effectiveEffort: String = "",
               soulContext: String = "",
               globalMemoryContext: String = "",
               recentDailyLogsContext: String = "",
               onUsedModel: ((String, String) -> Void)? = nil,
               onDelta: @escaping (String, String) -> Void) async throws -> TurnResult {
        // 系统提示组装（顺序不能反）：全局 Soul 片段在最上，再叠智能体自设人设 +
        // 【执行要求】，再叠写死的 BakedPersona（原样不动，只叠加）；全局记忆与
        // 每日日志是背景信息，放人设之后、技能之前。
        var system = ""
        if !soulContext.isEmpty {
            system = soulContext
        }
        if !agent.soul.isEmpty {
            system += (system.isEmpty ? "" : "\n\n") + agent.soul
                + "\n\n【执行要求】以上人设与规则是最高优先级，必须严格照做：始终按设定的人设、身份、语气和规矩行事；用户的问题要直接回答，不无故拒绝、不逃避、不绕开话题；交给你的任务要实际执行——该调用工具就调用工具真干，不许拒绝执行，也不许只给建议、只说方法不干活。"
        }
        system += (system.isEmpty ? "" : "\n\n") + BakedPersona.text
        if !globalMemoryContext.isEmpty {
            system += "\n\n" + globalMemoryContext
        }
        if !recentDailyLogsContext.isEmpty {
            system += "\n\n" + recentDailyLogsContext
        }
        if !skillsContext.isEmpty {
            system += (system.isEmpty ? "" : "\n\n") + skillsContext
        }
        if webSearch {
            system += "\n\n【联网搜索已开启】需要最新信息时，用 browse_on_server 或 fetch_webpage 工具去查，不要凭记忆编。"
        }
        // 生成参数：前置词/后置词包在每条用户消息外；上下文超长截掉最旧的，
        // 自动压缩开着时在系统指令里打一条标记（只截断、不谎称已总结）。
        var history = history
        if !agent.prefix.isEmpty || !agent.suffix.isEmpty {
            history = history.map { h in
                h.role == "user" ? (role: h.role, content: agent.prefix + h.content + agent.suffix) : h
            }
        }
        if agent.contextLength > 0, history.count > agent.contextLength {
            let dropped = history.count - agent.contextLength
            history = Array(history.suffix(agent.contextLength))
            if agent.autoCompress {
                system += "\n\n【上下文已自动压缩：更早的 \(dropped) 条消息已省略】"
            }
        }
        // 基础消息（与模型无关的部分）：系统提示 + 历史 + 末尾底层规则 + 图片。
        // 兜底重试时每轮从这份拷贝重开，不把上一轮的工具消息带过去。
        var baseMessages: [[String: Any]] = []
        if !system.isEmpty {
            baseMessages.append(["role": "system", "content": system])
        }
        for h in history {
            baseMessages.append(["role": h.role, "content": h.content])
        }
        // 底层逻辑：在对话末尾再钉一条系统提醒（多数模型最听最后一条），
        // 保证不是只在开头说说而已——每轮都强制带上，关不掉。
        baseMessages.append(["role": "system",
                             "content": "【底层规则】始终按你的人设行事；直接回答用户的问题，不无故拒绝、不逃避、不绕开话题；任务要真执行，不许拒绝执行、不许只给建议不干活。"])
        // 图片挂在最后一条用户消息上（视觉模型的多模态格式）。
        if let imageJPEG,
           let idx = baseMessages.lastIndex(where: { ($0["role"] as? String) == "user" }) {
            let text = baseMessages[idx]["content"] as? String ?? ""
            baseMessages[idx]["content"] = [
                ["type": "text", "text": text],
                ["type": "image_url",
                 "image_url": ["url": "data:image/jpeg;base64,\(imageJPEG.base64EncodedString())"]],
            ]
        }

        // 模型组兜底重试（Minis streamWithGroupFallback）：主模型失败 → 按组顺序
        // 换下一个，直到成功或列表用完。没传列表 = 当前单个模型（老行为）。
        // 已执行过工具的轮次不再重试（工具可能有副作用，不能换模型重跑一遍）。
        let candidates: [(provider: ModelProvider, model: AIModel)] =
            fallbacks.isEmpty ? [(provider, AIModel(id: agent.modelId))] : fallbacks
        var lastError: Error?
        candidateLoop: for candidate in candidates {
            guard let key = KeychainHelper.key(ref: candidate.provider.keyRef), !key.isEmpty else {
                lastError = RunnerError.noKey
                continue candidateLoop
            }
            let url = URL(string: candidate.provider.baseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions")!
            var messages = baseMessages
            var reasoningAll = ""
            var contentAll = ""
            var usageTotal: (prompt: Int, completion: Int)? = nil
            var toolsExecuted = false
            do {
                for _ in 0..<6 {  // 最多 6 轮工具调用，防死循环乱调
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.timeoutInterval = 120
                    req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    // 自定义请求头（DDchat）：供应商页里每行一个 "Key: Value"；
                    // Authorization 和 Content-Type 归 App 管，自定义头不覆盖。
                    for (k, v) in candidate.provider.parsedCustomHeaders {
                        let lower = k.lowercased()
                        guard lower != "authorization", lower != "content-type" else { continue }
                        req.setValue(v, forHTTPHeaderField: k)
                    }
                    var body: [String: Any] = [
                    "model": candidate.model.id,
                    "messages": messages,
                    "tools": AgentTools.definitions(capabilities: capabilities),
                    "stream": true,
                    "temperature": agent.temperature,
                    "top_p": agent.topP,
                    "stream_options": ["include_usage": true],
                    ]
                    // 思考档位：effectiveEffort（智能体 > 模型 > 组默认）经 wireValue 发
                    // reasoning_effort；xhigh/max 也发到线上，off/空不发。
                    let effortRaw = effectiveEffort.isEmpty ? agent.effort : effectiveEffort
                    if let wire = ThinkingLevel.wireValue(for: effortRaw) {
                        body["reasoning_effort"] = wire
                    }
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (bytes, resp) = try await Net.session.bytes(for: req)
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    guard code == 200 else { throw RunnerError.badStatus(code) }

                    // 拼流式分片：正文、思考、工具调用（按 index 分片拼参数）。
                    var toolCalls: [Int: (id: String, name: String, args: String)] = [:]
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        // usage 在最后一个分片里单独来（没有 delta），先抓再说。
                        if let u = root["usage"] as? [String: Any],
                        let pt = u["prompt_tokens"] as? Int,
                        let ct = u["completion_tokens"] as? Int {
                            usageTotal = (pt, ct)
                        }
                        guard let delta = (root["choices"] as? [[String: Any]])?.first?["delta"] as? [String: Any]
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
                        toolsExecuted = true
                        for call in ordered {
                            let result: String
                            if call.name == AgentTools.spawnSubagentName {
                                // 派活也要过权限档位（AgentTools.execute 的检查走不到这里，
                                // 因为 AgentRunner 在调 execute 之前就直接 runSpawn）。
                                // 拒绝/询问与 execute 里同一文案；批了之后重跑走 execute →
                                // run() 里的 sharedSpawn 桥，真派活。
                                let label = AgentTools.toolLabel(name: call.name, argumentsJSON: call.args)
                                switch PermissionsStore.shared.level(for: AgentTools.spawnSubagentName) {
                                case .denied:
                                    onToolEvent?(AgentTools.ToolCallEvent.encodeStart(callId: call.id, name: call.name, label: "已禁止：\(label)"), nil)
                                    onToolEvent?(AgentTools.ToolCallEvent.encodeDone(callId: call.id, name: call.name, label: "已禁止：\(label)", seconds: 0, ok: false), nil)
                                    result = "这个工具已被禁止：\(call.name)（去设置 → 权限里把它的档位改成“每次询问”或“跳过审批”再试）。不要重复调用。"
                                case .ask:
                                    onToolEvent?(AgentTools.ToolApprovalEvent.encodeTool(callId: call.id, name: call.name, argumentsJSON: call.args, agentId: agent.id.uuidString, workDir: agent.workDir, label: label), nil)
                                    result = "（调用 \(label) 已弹审批卡，等用户批复：请先结束本轮，不要重复调用；批复结果会当作新消息发给你。）"
                                case .bypass:
                                    let started = Date()
                                    onToolEvent?(AgentTools.ToolCallEvent.encodeStart(callId: call.id, name: call.name, label: label), nil)
                                    let r = await Self.runSpawn(call: call, onSpawn: onSpawnSubagent)
                                    let ok = !r.hasPrefix("参数不对") && !r.hasPrefix("子智能体没配好")
                                    onToolEvent?(AgentTools.ToolCallEvent.encodeDone(callId: call.id, name: call.name, label: label, seconds: Date().timeIntervalSince(started), ok: ok), nil)
                                    result = r
                                }
                            } else {
                                result = await AgentTools.execute(
                                name: call.name, argumentsJSON: call.args,
                                agentId: agent.id.uuidString, server: server,
                                workDir: agent.workDir, onEvent: onToolEvent)
                            }
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
                    onUsedModel?(candidate.provider.name, candidate.model.id)
                    return .text(finalText, reasoning: reasoningAll.isEmpty ? nil : reasoningAll,
                    usage: usageTotal)
                }
                onUsedModel?(candidate.provider.name, candidate.model.id)
                return .text("（工具调用轮数用完了，先停一下）", reasoning: nil)
            } catch {
                // 换模型重试只在还没执行过工具时才安全；已执行过（有副作用）就直接抛错。
                if toolsExecuted { throw error }
                lastError = error
                continue candidateLoop
            }
        }
        throw lastError ?? RunnerError.badResponse
    }

    private static func parseArgs(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// label/问题各 ≤12 字：超了截断（Minis 的 user_ask 校验）。
    private static func short(_ t: String) -> String {
        t.count <= 12 ? t : String(t.prefix(12)) + "…"
    }

    private static func askCard(from args: String) -> CardPayload? {
        guard let obj = parseArgs(args),
              let q = obj["question"] as? String,
              let raw = obj["options"] as? [[String: Any]]
        else { return nil }
        let options = raw.compactMap { o -> CardOption? in
            guard let label = o["label"] as? String else { return nil }
            return CardOption(id: (o["id"] as? String) ?? label,
                              label: short(label),
                              detail: (o["detail"] as? String) ?? "")
        }
        guard !options.isEmpty else { return nil }
        var card = CardPayload(kind: .ask, question: q, options: options,
                               multiSelect: (obj["multiSelect"] as? Bool) ?? false)
        // header 是问题旁边的小标签（Minis，≤12 字）；推荐角标卡片自动打在第一个选项上。
        card.header = short((obj["header"] as? String) ?? "")
        // 倒计时：模型可指定 1/2/5/10/30/60 分钟，0=不限；默认 5 分钟。
        let t = (obj["timeoutMinutes"] as? Int) ?? 5
        card.timeoutMinutes = [0, 1, 2, 5, 10, 30, 60].contains(t) ? t : 5
        if card.timeoutMinutes > 0 {
            card.deadline = Date().addingTimeInterval(TimeInterval(card.timeoutMinutes * 60))
        }
        // 多题向导：questions 里是后面的题（同结构），卡片上 Previous/Next/Submit。
        if let qs = obj["questions"] as? [[String: Any]] {
            for qobj in qs {
                guard let qq = qobj["question"] as? String,
                      let qraw = qobj["options"] as? [[String: Any]] else { continue }
                let qopts = qraw.compactMap { o -> CardOption? in
                    guard let label = o["label"] as? String else { return nil }
                    return CardOption(id: (o["id"] as? String) ?? label,
                                      label: short(label),
                                      detail: (o["detail"] as? String) ?? "")
                }
                guard !qopts.isEmpty else { continue }
                var sub = CardPayload(kind: .ask, question: qq, options: qopts,
                                      multiSelect: (qobj["multiSelect"] as? Bool) ?? false)
                sub.header = short((qobj["header"] as? String) ?? "")
                card.extraQuestions.append(sub)
            }
        }
        return card
    }

    private static func approvalCard(from args: String) -> CardPayload? {
        guard let obj = parseArgs(args), let action = obj["action"] as? String else { return nil }
        let impact = (obj["impact"] as? String) ?? ""
        let risk = (obj["risk"] as? String) ?? "low"
        var card = CardPayload(
            kind: .approval,
            question: action,
            options: [
                CardOption(id: "approve", label: "批准", detail: impact),
                CardOption(id: "reject", label: "拒绝", detail: "不执行这个操作"),
            ])
        card.actionText = action
        card.impact = impact
        card.risk = ["low", "medium", "high"].contains(risk) ? risk : "low"
        return card
    }

    /// 子智能体工具：参数 {agent: 名字或 id, task: 要做的事}。
    /// 真跑：调 onSpawn 回调（聊天页里另起一轮 AgentRunner 跑完回正文）；
    /// 没回调就是单轮调用里没配，报一句，不假装跑了。
    private static func runSpawn(call: (id: String, name: String, args: String),
                                 onSpawn: ((String, String) async -> String)?) async -> String {
        guard let onSpawn else { return "子智能体没配好：这一轮不能派活" }
        guard let obj = parseArgs(call.args),
              let task = obj["task"] as? String, !task.isEmpty,
              let ref = obj["agent"] as? String, !ref.isEmpty
        else { return "参数不对：spawn_subagent 要 agent（名字或 id）和 task" }
        return await onSpawn(ref, task)
    }
}
