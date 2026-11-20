import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// 助手复制 / 导入 / 分享（DDchat 补 4）。
///
/// 商店原文：「支持复制、导入和分享助手。」
/// 核查（DDCHAT_SUPPLEMENT.md 补 4）：ChatImport.swift 只有会话导入，
/// grep 分享助手/导出助手/导入助手零命中。
///
/// 落法（按补单建议）：编辑页加复制（改名另存一份）、导出/导入（JSON，含名字、人设、
/// 前置/后置词、参数、默认模型，不含 Key）、分享（系统分享单）。
/// 与 #7 会话导入共用文件导入管线（.fileImporter 读 .json）。

enum AgentShare {
    /// 助手导出格式（JSON）。version 留给以后兼容；不含任何 Key（Key 在钥匙串里，不跟助手走）。
    struct Export: Codable {
        var version: Int = 1
        var name: String
        var soul: String = ""
        var providerKey: String = ""
        var modelId: String = ""
        var effort: String = ""
        var prefix: String = ""
        var suffix: String = ""
        var temperature: Double = 1.0
        var topP: Double = 1.0
        var contextLength: Int = 0
        var autoCompress: Bool = false
        var workDir: String = ""
        var isPrivate: Bool = false
        var tintHue: Double = 0.6
    }

    static func export(of agent: Agent) -> Export {
        Export(name: agent.name, soul: agent.soul, providerKey: agent.providerKey,
               modelId: agent.modelId, effort: agent.effort, prefix: agent.prefix,
               suffix: agent.suffix, temperature: agent.temperature, topP: agent.topP,
               contextLength: agent.contextLength, autoCompress: agent.autoCompress,
               workDir: agent.workDir, isPrivate: agent.isPrivate, tintHue: agent.tintHue)
    }

    static func jsonData(of agent: Agent) -> Data? {
        try? JSONEncoder().encode(export(of: agent))
    }

    static func jsonString(of agent: Agent) -> String? {
        guard let data = jsonData(of: agent) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 解析导入的 JSON。名字为空、或根本不是助手 JSON 时返回 nil（调用方给明确提示）。
    static func decode(_ data: Data) -> Export? {
        guard let e = try? JSONDecoder().decode(Export.self, from: data),
              !e.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return e
    }

    static func agent(from export: Export) -> Agent {
        var a = Agent(name: export.name, tintHue: export.tintHue)
        a.soul = export.soul
        a.providerKey = export.providerKey
        a.modelId = export.modelId
        a.effort = export.effort
        a.prefix = export.prefix
        a.suffix = export.suffix
        a.temperature = export.temperature
        a.topP = export.topP
        a.contextLength = export.contextLength
        a.autoCompress = export.autoCompress
        a.workDir = export.workDir
        a.isPrivate = export.isPrivate
        return a
    }

    /// 复制一份：改名另存（名字后加“副本”，重名自动加序号），返回新智能体。
    @discardableResult
    static func duplicate(store: AppStore, agent: Agent) -> Agent {
        var name = agent.name + " 副本"
        var n = 2
        while store.agents.contains(where: { $0.name == name }) {
            name = agent.name + " 副本 \(n)"
            n += 1
        }
        var copy = agent
        copy.id = UUID()
        copy.name = name
        store.agents.append(copy)
        store.save()
        return copy
    }

    /// 导出 JSON 到剪贴板（给别的设备 / 别人粘贴导入用）。
    static func copyJSONToClipboard(agent: Agent) -> Bool {
        guard let s = jsonString(of: agent) else { return false }
        UIPasteboard.general.string = s
        return true
    }

    /// 从剪贴板导入：剪贴板里是助手 JSON 就新建一个智能体；不是则返回失败原因。
    static func importFromClipboard(store: AppStore) -> Result<Agent, String> {
        guard let s = UIPasteboard.general.string,
              let data = s.data(using: .utf8),
              let e = decode(data)
        else { return .failure("剪贴板里没有助手 JSON：先在别的助手上点“导出 JSON 到剪贴板”再来。") }
        let a = agent(from: e)
        store.agents.append(a)
        store.save()
        return .success(a)
    }

    /// 从文件数据导入（.fileImporter 读到的 Data 走这里）。
    static func importFromData(_ data: Data, store: AppStore) -> Result<Agent, String> {
        guard let e = decode(data) else {
            return .failure("这个文件不是助手 JSON：确认是从 OpenQuest 导出的助手文件。")
        }
        let a = agent(from: e)
        store.agents.append(a)
        store.save()
        return .success(a)
    }
}

/// 系统分享单（UIActivityViewController）：分享助手 JSON 文件。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// 助手编辑页里的“复制 / 导入 / 分享”按钮组（AgentEditView 里直接嵌这个视图）。
struct AgentShareButtons: View {
    @EnvironmentObject var store: AppStore
    let agentId: UUID

    @State private var status: String?
    @State private var shareItems: [Any]?
    @State private var showFileImporter = false

    private var agent: Agent? { store.agent(id: agentId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let a = agent {
                Button("复制一份（改名另存）") {
                    let copy = AgentShare.duplicate(store: store, agent: a)
                    status = "已复制一份：「\(copy.name)」"
                }
                Button("导出 JSON 到剪贴板") {
                    status = AgentShare.copyJSONToClipboard(agent: a)
                        ? "助手 JSON 已复制到剪贴板，粘贴到别处就能导入。"
                        : "导出失败，再试一次。"
                }
                Button("分享助手") {
                    if let data = AgentShare.jsonData(of: a) {
                        let url = FileManager.default.temporaryDirectory
                            .appendingPathComponent("助手-\(a.name).json")
                        try? data.write(to: url)
                        shareItems = [url]
                    } else {
                        status = "导出失败，再试一次。"
                    }
                }
                Button("从剪贴板导入") {
                    switch AgentShare.importFromClipboard(store: store) {
                    case .success(let imported):
                        status = "已导入助手「\(imported.name)」"
                    case .failure(let msg):
                        status = msg
                    }
                }
                Button("从文件导入助手 JSON") {
                    showFileImporter = true
                }
                if let status {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("这个智能体不存在了")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                guard url.startAccessingSecurityScopedResource() else {
                    status = "打不开这个文件，换一个再试。"
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                guard let data = try? Data(contentsOf: url) else {
                    status = "读不到这个文件的内容。"
                    return
                }
                switch AgentShare.importFromData(data, store: store) {
                case .success(let imported):
                    status = "已导入助手「\(imported.name)」"
                case .failure(let msg):
                    status = msg
                }
            case .failure:
                status = "没选到文件。"
            }
        }
        .sheet(item: Binding(
            get: { shareItems.map { ShareItemsBox(items: $0) } },
            set: { shareItems = $0?.items }
        )) { box in
            ShareSheet(items: box.items)
        }
    }
}

/// .sheet(item:) 要 Identifiable，包一层。
private struct ShareItemsBox: Identifiable {
    let id = UUID()
    let items: [Any]
}
