import SwiftUI

/// 插件商店（FishPocket 式）：索引源是第三方的，须用户手动启用、一次只用一个，
/// 列表里写明是第三方。安装时识别 Client 半：带网页界面且无主机部分的插件，
/// 明确提示“网页界面部分在 App 内无法运行，只跑主机部分”，不静默装。
struct PluginStoreView: View {
    @EnvironmentObject var store: AppStore
    @State private var entries: [StoreEntry] = []
    @State private var busy = false
    @State private var status: String?
    @State private var pendingInstall: StoreEntry?
    @State private var pendingClientHalf = false

    struct StoreEntry: Identifiable {
        var id: String { name + (manifestURL ?? "") }
        var name: String
        var summary: String
        var manifestURL: String?
        var manifest: [String: Any]?
    }

    private let indexes: [(id: String, name: String, url: String)] = [
        ("dsh-market", "第三方插件索引 1",
         "https://cdn.jsdelivr.net/gh/realguan/dsh-plugin-market@dist/dsh-index.json"),
        ("dshfind", "第三方插件索引 2",
         "https://api.dshfind.com/market/dsh-index.json"),
    ]

    var body: some View {
        List {
            Section("索引源（第三方，一次只用一个）") {
                ForEach(indexes, id: \.id) { idx in
                    Button {
                        if store.pluginStoreIndex == idx.id {
                            store.pluginStoreIndex = ""
                            store.save()
                            entries = []
                        } else {
                            store.pluginStoreIndex = idx.id
                            store.save()
                            Task { await loadIndex(url: idx.url) }
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(idx.name).foregroundStyle(.primary)
                                Text(idx.url).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.pluginStoreIndex == idx.id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }
                }
                Text("商店索引是第三方维护的列表，App 不自营市场。点一下启用，再点一下关掉。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let status {
                Section { Text(status).font(.footnote).foregroundStyle(.secondary) }
            }
            Section("插件") {
                if busy { ProgressView() }
                if entries.isEmpty && !busy && !store.pluginStoreIndex.isEmpty {
                    Text("这个索引里没有可装的插件，或者拉取失败。")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { e in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.name)
                                if !e.summary.isEmpty {
                                    Text(e.summary).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("安装") { Task { await prepareInstall(e) } }
                                .font(.subheadline)
                                .disabled(busy)
                        }
                    }
                }
            }
        }
        .navigationTitle("插件商店")
        .alert("带网页界面部分", isPresented: $pendingClientHalf) {
            Button("只装主机部分") {
                if let e = pendingInstall { Task { await install(e, allowClientHalf: true) } }
            }
            Button("取消", role: .cancel) { pendingInstall = nil }
        } message: {
            Text("这个插件带网页界面部分，App 内无法运行网页界面，只能跑它的主机部分（工具、指令、后台任务）。只装主机部分吗？")
        }
    }

    /// 拉索引：顶层数组或 {plugins/items/bundles: [...]} 都认。
    private func loadIndex(url urlString: String) async {
        busy = true
        defer { busy = false }
        guard let url = URL(string: urlString) else {
            status = "索引地址不对"
            return
        }
        do {
            let (data, resp) = try await Net.session.data(from: url)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                status = "索引拉取失败（\(code)）"
                return
            }
            guard let root = try? JSONSerialization.jsonObject(with: data) else {
                status = "索引格式看不懂"
                return
            }
            var raw: [[String: Any]] = []
            if let arr = root as? [[String: Any]] { raw = arr }
            else if let dict = root as? [String: Any] {
                for key in ["plugins", "items", "bundles", "entries"] {
                    if let arr = dict[key] as? [[String: Any]] { raw = arr; break }
                }
            }
            entries = raw.compactMap { o in
                guard let name = (o["name"] as? String), !name.isEmpty else { return nil }
                return StoreEntry(
                    name: name,
                    summary: (o["description"] as? String) ?? (o["desc"] as? String) ?? "",
                    manifestURL: (o["manifestUrl"] as? String) ?? (o["manifest"] as? String)
                        ?? (o["url"] as? String) ?? (o["downloadUrl"] as? String),
                    manifest: nil)
            }
            status = entries.isEmpty ? "索引里没有插件" : "拉到 \(entries.count) 个插件"
        } catch {
            status = "索引拉取失败：\(error.localizedDescription)"
        }
    }

    /// 安装前：先拿到清单 JSON，判断有没有 Client 半。
    private func prepareInstall(_ e: StoreEntry) async {
        guard let urlString = e.manifestURL, let url = URL(string: urlString) else {
            status = "这个条目没有清单地址，装不了"
            return
        }
        busy = true
        defer { busy = false }
        do {
            let (data, _) = try await Net.session.data(from: url)
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                status = "清单格式看不懂"
                return
            }
            var entry = e
            entry.manifest = obj
            if Plugin.manifestHasClientHalf(obj) {
                pendingInstall = entry
                pendingClientHalf = true
            } else {
                await install(entry, allowClientHalf: false)
            }
        } catch {
            status = "清单下载失败：\(error.localizedDescription)"
        }
    }

    /// 按插件页同一套规则安装：主题类拦下，英文名/说明自动译中文，默认关。
    private func install(_ e: StoreEntry, allowClientHalf: Bool) async {
        guard let obj = e.manifest else { return }
        let type = (obj["type"] as? String) ?? "instruction"
        if type == "theme" || type == "web" || type == "skin" {
            status = "这个是纯网页美化类插件，App 里没有它的运行环境，装不了。"
            return
        }
        let rawName = (obj["name"] as? String) ?? e.name
        let content = (obj["content"] as? String)
            ?? (obj["instructions"] as? String)
            ?? (obj["script"] as? String) ?? ""
        let summary = (obj["description"] as? String) ?? (obj["desc"] as? String) ?? e.summary
        let settingsURL = (obj["settingsURL"] as? String) ?? (obj["settingsUrl"] as? String) ?? ""
        let (name, desc) = await store.translatePluginText(name: rawName, summary: summary)
        store.addPlugin(Plugin(name: name, summary: desc,
                               type: type == "script" ? "script" : "instruction",
                               content: content, settingsURL: settingsURL,
                               hasClientHalf: allowClientHalf))
        status = "装好了「\(name)」，默认关着，去插件列表里打开才生效。"
    }
}
