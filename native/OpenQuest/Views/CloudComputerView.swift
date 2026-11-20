import SwiftUI

/// 云电脑页：用户自己的 ECS 常驻主机（47.238.160.204:18789）的终端 + 文件 + 浏览器入口。
/// 手机只是窗口，真正的电脑在服务器上——跟捷风一样的调用方式。
struct CloudComputerView: View {
    @EnvironmentObject var store: AppStore
    @State private var health: ServerClient.HealthResult?
    @State private var healthError: String?
    @State private var healthBusy = false
    @State private var command = ""
    @State private var output = ""
    @State private var exitCode: Int?
    @State private var execBusy = false
    @State private var entries: [ServerClient.FileEntry] = []
    @State private var filesError: String?
    @State private var filesBusy = false
    @State private var currentPath = ""
    @State private var fileContent: String?
    @State private var fileContentName = ""
    @State private var showBrowser = false

    /// 服务器上的工作区归属：直接聊的智能体用 "user"，跟服务器浏览器同一份资料。
    private var botName: String { "user" }

    private var uptimeText: String {
        guard let h = health else { return "" }
        let s = h.uptime_s
        if s < 3600 { return "\(s / 60) 分钟" }
        if s < 86400 { return "\(s / 3600) 小时" }
        return "\(s / 86400) 天"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusCard
                terminalCard
                filesCard
                browserCard
            }
            .padding(16)
        }
        .background(Palette.background)
        .navigationTitle("云电脑")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshHealth()
            await refreshFiles()
        }
        .overlay {
            if showBrowser {
                MiniWindow(title: "服务器浏览器", onClose: { showBrowser = false }) {
                    BrowserView()
                }
            }
        }
    }

    // MARK: 状态

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusDot(kind: health != nil ? .running : .idle)
                Text(health != nil ? "云电脑在线" : "云电脑未连接")
                    .font(.headline)
                Spacer()
                Button("刷新") { Task { await refreshHealth() } }
                    .font(.subheadline)
                    .disabled(healthBusy)
            }
            if let h = health {
                Text("openquest-bot-host · 版本 \(h.version) · 已运行 \(uptimeText)")
                    .font(.caption).foregroundStyle(.secondary)
                Text("主机 \(store.server.host):\(store.server.port) · 常驻智能体 \(h.bots.count) 个")
                    .font(.caption).foregroundStyle(.secondary)
                if let mem = h.mem_available_mb {
                    Text("可用内存 \(mem) MB")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if let err = healthError {
                Text(err).font(.caption).foregroundStyle(.red)
                Text("令牌在打包时注入；仓库里的构建没有令牌，连不上是正常的。")
                    .font(.caption).foregroundStyle(.secondary)
            } else if healthBusy {
                ProgressView().controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.field, in: RoundedRectangle(cornerRadius: 20))
    }

    private func refreshHealth() async {
        healthBusy = true
        defer { healthBusy = false }
        do {
            health = try await ServerClient(config: store.server).health()
            healthError = nil
        } catch {
            health = nil
            healthError = error.localizedDescription
        }
    }

    // MARK: 终端

    private var terminalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("终端").font(.headline)
            HStack(spacing: 8) {
                TextField("输入命令，如：ls", text: $command)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(.body, design: .monospaced))
                    .padding(10)
                    .background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.stroke, lineWidth: 1))
                    .onSubmit { Task { await runCommand() } }
                Button("运行") { Task { await runCommand() } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.onInk)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Palette.ink, in: Capsule())
                    .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty || execBusy)
            }
            if execBusy {
                ProgressView().controlSize(.small)
            } else if !output.isEmpty {
                ScrollView {
                    Text(output)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 220)
                .padding(10)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.stroke, lineWidth: 1))
            }
            if let code = exitCode {
                Text(code == 0 ? "退出码 0" : "退出码 \(code)")
                    .font(.caption)
                    .foregroundStyle(code == 0 ? Palette.running : .red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.field, in: RoundedRectangle(cornerRadius: 20))
    }

    private func runCommand() async {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        execBusy = true
        defer { execBusy = false }
        do {
            let r = try await ServerClient(config: store.server).exec(agentId: botName, command: cmd)
            exitCode = r.exitCode
            let err = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            output = r.stdout + (err.isEmpty ? "" : "\n" + err)
            if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                output = "（没有输出）"
            }
        } catch {
            exitCode = nil
            output = "出错了：" + error.localizedDescription
        }
    }

    // MARK: 文件

    private var filesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("文件").font(.headline)
                Spacer()
                if !currentPath.isEmpty {
                    Button("上级") {
                        var parts = currentPath.split(separator: "/").map(String.init)
                        parts.removeLast()
                        currentPath = parts.joined(separator: "/")
                        Task { await refreshFiles() }
                    }
                    .font(.subheadline)
                }
            }
            Text(currentPath.isEmpty ? "工作区 /" : "工作区 /" + currentPath)
                .font(.caption).foregroundStyle(.secondary)
            if filesBusy {
                ProgressView().controlSize(.small)
            } else if let err = filesError {
                Text(err).font(.caption).foregroundStyle(.red)
            } else if entries.isEmpty {
                Text("这个文件夹是空的").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(entries) { e in
                    Button {
                        if e.dir {
                            currentPath = currentPath.isEmpty ? e.name : currentPath + "/" + e.name
                            Task { await refreshFiles() }
                        } else {
                            Task { await readFile(e.name) }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: e.dir ? "folder.fill" : "doc.fill")
                                .foregroundStyle(e.dir ? Palette.waiting : Palette.secondary)
                            Text(e.name).font(.subheadline).lineLimit(1)
                            Spacer()
                            if let size = e.size {
                                Text("\(size) B").font(.caption).foregroundStyle(.secondary)
                            }
                            if e.dir {
                                Image(systemName: "chevron.right")
                                    .font(.caption2).foregroundStyle(Palette.faint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Divider().background(Palette.stroke)
                }
            }
            if let content = fileContent {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(fileContentName).font(.caption.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Button { fileContent = nil } label: {
                            Image(systemName: "xmark").font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                    ScrollView {
                        Text(content)
                            .font(.system(size: 13, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 180)
                }
                .padding(10)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.stroke, lineWidth: 1))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.field, in: RoundedRectangle(cornerRadius: 20))
    }

    private func refreshFiles() async {
        filesBusy = true
        defer { filesBusy = false }
        do {
            entries = try await ServerClient(config: store.server)
                .filesList(bot: botName, path: currentPath)
            filesError = nil
        } catch {
            entries = []
            filesError = error.localizedDescription
        }
    }

    private func readFile(_ name: String) async {
        let path = currentPath.isEmpty ? name : currentPath + "/" + name
        do {
            let text = try await ServerClient(config: store.server).filesRead(bot: botName, path: path)
            fileContentName = name
            fileContent = String(text.prefix(4000))
        } catch {
            fileContentName = name
            fileContent = "读不出来：" + error.localizedDescription
        }
    }

    // MARK: 浏览器

    private var browserCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("浏览器").font(.headline)
            Text("服务器上的浏览器：登录状态保存在服务器，手机只看画面、点画面。")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                showBrowser = true
            } label: {
                Label("打开服务器浏览器", systemImage: "globe")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.onInk)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Palette.ink, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.field, in: RoundedRectangle(cornerRadius: 20))
    }
}
