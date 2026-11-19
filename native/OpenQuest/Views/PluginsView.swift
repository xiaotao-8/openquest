import SwiftUI
import WebKit

/// DNS 设置：预设阿里/腾讯/114 + 自定义，默认跟随系统（关），手动开。
/// 开了真生效于 App 自己的请求（模型、服务器、抓网页）——走 NetDNS 那套。
struct DNSSettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var customText = ""

    private func row(mode: String, title: String, detail: String) -> some View {
        Button {
            store.setDNS(mode: mode)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if store.dnsMode == mode {
                    Image(systemName: "checkmark").foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        List {
            Section {
                row(mode: "system", title: "跟随系统", detail: "默认。用手机系统自带的解析")
                row(mode: "ali", title: "阿里 DNS", detail: "223.5.5.5")
                row(mode: "tencent", title: "腾讯 DNS", detail: "119.29.29.29")
                row(mode: "114", title: "114 DNS", detail: "114.114.114.114")
                row(mode: "custom", title: "自定义", detail: store.dnsCustom.isEmpty ? "填一个 DNS 服务器 IP" : store.dnsCustom)
            }
            if store.dnsMode == "custom" {
                Section("自定义 DNS 服务器") {
                    HStack {
                        TextField("如 223.6.6.6", text: $customText)
                            .keyboardType(.decimalPad)
                            .autocorrectionDisabled()
                        Button("应用") {
                            let v = customText.trimmingCharacters(in: .whitespaces)
                            if !v.isEmpty { store.setDNS(mode: "custom", custom: v) }
                        }
                        .disabled(customText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            Section {
                Text("只影响这个 App 自己的网络请求（聊天、服务器、抓网页），不改系统全局。解析失败会自动回退系统解析，不会把网络弄断。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("DNS")
        .onAppear { customText = store.dnsCustom }
    }
}

/// 插件（DSH 风格）：在 App 内下载/粘贴安装单文件插件包，开关控制，
/// 指令类真进系统提示、脚本类在服务器上真跑、设置页用内嵌网页打开；
/// 纯网页美化类装不进来，安装时就拦下说明。英文名/说明自动译中文。
struct PluginsView: View {
    @EnvironmentObject var store: AppStore
    @State private var urlText = ""
    @State private var pasteText = ""
    @State private var status: String?
    @State private var busy = false
    @State private var runOutput: (name: String, text: String)?
    @State private var webSettings: Plugin?

    var body: some View {
        List {
            Section("从链接安装") {
                HStack {
                    TextField("插件包地址（.json）", text: $urlText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("安装") { Task { await installFromURL() } }
                        .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                }
            }
            Section("粘贴清单安装") {
                TextEditor(text: $pasteText)
                    .frame(height: 90)
                    .font(.caption)
                Button("按粘贴内容安装") { Task { await installFromText(pasteText) } }
                    .disabled(pasteText.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }
            if let status {
                Section { Text(status).font(.footnote).foregroundStyle(.secondary) }
            }
            Section("已装插件") {
                if store.plugins.isEmpty {
                    Text("还没装插件").foregroundStyle(.secondary)
                }
                ForEach(store.plugins) { p in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name)
                                if !p.summary.isEmpty {
                                    Text(p.summary).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(typeLabel(p.type))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color.white.opacity(0.09), in: Capsule())
                            Toggle("", isOn: Binding(
                                get: { p.enabled },
                                set: { store.setPluginEnabled(id: p.id, $0) }
                            ))
                            .labelsHidden()
                        }
                        HStack(spacing: 14) {
                            if p.type == "script" {
                                Button("在服务器上运行") { Task { await runScript(p) } }
                                    .font(.caption)
                            }
                            if !p.settingsURL.isEmpty {
                                Button("插件设置") { webSettings = p }
                                    .font(.caption)
                            }
                            Button("删除", role: .destructive) { store.deletePlugin(id: p.id) }
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            Section {
                Text("指令类插件启用后对所有智能体生效；脚本类点「运行」在你的服务器上真执行；纯网页美化类插件 App 里用不了，安装时会被拦下。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("插件")
        .sheet(item: $webSettings) { p in
            NavigationStack {
                PluginWebView(urlString: p.settingsURL)
                    .navigationTitle("\(p.name) 设置")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("关闭") { webSettings = nil }
                        }
                    }
            }
        }
        .sheet(item: Binding(
            get: { runOutput.map { RunSheet(name: $0.name, text: $0.text) } },
            set: { if $0 == nil { runOutput = nil } }
        )) { sheet in
            NavigationStack {
                ScrollView {
                    Text(sheet.text)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .textSelection(.enabled)
                }
                .background(Color.black)
                .navigationTitle("\(sheet.name) 运行结果")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("关闭") { runOutput = nil }
                    }
                }
            }
        }
    }

    private struct RunSheet: Identifiable {
        var id: String { name }
        let name: String
        let text: String
    }

    private func typeLabel(_ t: String) -> String {
        switch t {
        case "script": return "脚本"
        case "theme": return "美化"
        default: return "指令"
        }
    }

    private func installFromURL() async {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespaces)) else {
            status = "地址不对"
            return
        }
        busy = true
        defer { busy = false }
        do {
            let (data, _) = try await Net.session.data(from: url)
            guard let text = String(data: data, encoding: .utf8) else {
                status = "下载到的不是文本清单"
                return
            }
            await installFromText(text)
            if status?.hasPrefix("装好了") == true { urlText = "" }
        } catch {
            status = "下载失败：\(error.localizedDescription)"
        }
    }

    /// 解析单文件清单 JSON：{name, description, type, content/instructions/script, settingsURL}
    private func installFromText(_ text: String) async {
        busy = true
        defer { busy = false }
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawName = obj["name"] as? String, !rawName.isEmpty
        else {
            status = "清单格式看不懂：要一个含 name 的 JSON"
            return
        }
        let type = (obj["type"] as? String) ?? "instruction"
        if type == "theme" || type == "web" || type == "skin" {
            status = "这个是纯网页美化类插件，靠改网页界面工作，App 里没有它的运行环境，装不了。换指令类或脚本类插件。"
            return
        }
        let content = (obj["content"] as? String)
            ?? (obj["instructions"] as? String)
            ?? (obj["script"] as? String) ?? ""
        let summary = (obj["description"] as? String) ?? (obj["desc"] as? String) ?? ""
        let settingsURL = (obj["settingsURL"] as? String) ?? (obj["settingsUrl"] as? String) ?? ""
        let (name, desc) = await store.translatePluginText(name: rawName, summary: summary)
        store.addPlugin(Plugin(name: name, summary: desc,
                               type: type == "script" ? "script" : "instruction",
                               content: content, settingsURL: settingsURL))
        status = "装好了「\(name)」，默认关着，去列表里打开才生效。"
        pasteText = ""
    }

    /// 脚本类插件：在服务器上真跑（base64 传过去解码执行，输出原样带回）。
    private func runScript(_ p: Plugin) async {
        busy = true
        defer { busy = false }
        let b64 = Data(p.content.utf8).base64EncodedString()
        let path = "/tmp/oq-plugin-\(p.id.uuidString.prefix(8)).sh"
        let cmd = "echo \(b64) | base64 -d > \(path) && bash \(path)"
        do {
            let r = try await ServerClient(config: store.server).exec(agentId: "user", command: cmd)
            var out = "退出码 \(r.exitCode)"
            if !r.stdout.isEmpty { out += "\n\(r.stdout)" }
            if !r.stderr.isEmpty { out += "\n[stderr]\n\(r.stderr)" }
            runOutput = (p.name, out)
        } catch {
            runOutput = (p.name, "运行失败：\(error.localizedDescription)")
        }
    }
}

/// 插件的网页设置页：内嵌网页视图，不用跳去网页版。
struct PluginWebView: UIViewRepresentable {
    let urlString: String
    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView()
        if let url = URL(string: urlString) {
            web.load(URLRequest(url: url))
        }
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
