import Foundation

/// 模型能力自动检测（DDchat）：从模型 id/显示名推断是否支持深度思考、视觉理解。
/// 只作提示，不拦着用——没检测出的按支持处理（nil），界面控件照常显示；
/// 只有明确不带该能力的类型（embedding / 语音 / 画图等）才标 false。
enum ModelCapabilities {
    /// 返回 (supportsReasoning, supportsVision)，任一都可能为 nil（没检测出）。
    static func detect(id: String, displayName: String = "") -> (supportsReasoning: Bool?, supportsVision: Bool?) {
        let hay = (id + " " + displayName).lowercased()
        // 明确不是聊天模型的类型：两项都标 false，思考档位和发图片收起来。
        let nonChat = ["embedding", "embed", "tts", "whisper", "rerank", "reranker",
                       "moderation", "dall-e", "sora", "text-to-image", "image-gen",
                       "audio", "speech", "asr"]
        if nonChat.contains(where: { hay.contains($0) }) {
            return (false, false)
        }
        var reasoning: Bool? = nil
        if ["reasoning", "think", "r1", "o1", "o3", "o4", "qwq", "reasoner"].contains(where: { hay.contains($0) }) {
            reasoning = true
        }
        var vision: Bool? = nil
        if ["vision", "vl", "4o", "multimodal", "multimodel"].contains(where: { hay.contains($0) }) {
            vision = true
        }
        return (reasoning, vision)
    }

    /// 给一个模型打上检测结果（只在拉取列表/手动添加时调）。
    static func applying(to model: AIModel) -> AIModel {
        var m = model
        let d = detect(id: m.id, displayName: m.displayName)
        m.supportsReasoning = d.supportsReasoning
        m.supportsVision = d.supportsVision
        return m
    }
}
