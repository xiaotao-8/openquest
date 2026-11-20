import SwiftUI

/// 语言设置：六种语言，换了立即生效（核心界面字符串走 L10n 表）。
struct LanguageSettingsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        List {
            ForEach(L10n.languages, id: \.code) { lang in
                Button {
                    store.language = lang.code
                    store.save()
                } label: {
                    HStack {
                        Text(lang.name).foregroundStyle(.primary)
                        Spacer()
                        if store.language == lang.code {
                            Image(systemName: "checkmark").foregroundStyle(.blue)
                        }
                    }
                }
            }
            Section {
                Text("换语言后核心界面（标签栏、设置、聊天列表、输入框）立即切换；个别深层页面下次打开时切换。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("语言")
    }
}

/// 用量统计：全部会话的回复用量合计 + 按智能体分。
struct UsageStatsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        List {
            Section("合计") {
                HStack {
                    Text("输入")
                    Spacer()
                    Text("\(store.totalUsage.prompt) tokens")
                }
                HStack {
                    Text("输出")
                    Spacer()
                    Text("\(store.totalUsage.completion) tokens")
                }
                HStack {
                    Text("总计")
                    Spacer()
                    Text("\(store.totalUsage.prompt + store.totalUsage.completion) tokens")
                        .font(.body.weight(.semibold))
                }
            }
            Section("按智能体") {
                if store.usageByAgent().isEmpty {
                    Text("还没有带用量的回复。聊过天之后，这里按智能体统计输入/输出。")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.usageByAgent(), id: \.name) { row in
                    HStack {
                        Text(row.name)
                        Spacer()
                        Text("入 \(row.prompt) · 出 \(row.completion)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Text("用量取每次回复的 SSE usage 段（输入/输出 token 数），存在每条回复下面；换模型、清会话都会跟着变。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("用量统计")
    }
}

/// 检查更新：查一次 ECS 版本源，有新版弹窗提示下载（签名一步绕不开）。
struct UpdateView: View {
    @EnvironmentObject var store: AppStore
    @State private var status: String?
    @State private var feed: UpdateChecker.Feed?
    @State private var busy = false

    var body: some View {
        List {
            Section {
                Button {
                    Task { await check() }
                } label: {
                    HStack {
                        Text("检查更新").foregroundStyle(.primary)
                        Spacer()
                        if busy { ProgressView() }
                    }
                }
                .disabled(busy)
                if let status {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                Text("版本源在你的服务器上，每次打开 App 也会查一次。有新版会弹窗提示下载，下载后去签名工具重签安装——免费签名下这一步绕不开，这是最接近直接更新的做法。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("检查更新")
        .alert("有新版本", isPresented: Binding(
            get: { feed != nil },
            set: { if !$0 { feed = nil } }
        )) {
            Button("去下载") {
                if let urlString = feed?.url, let url = URL(string: urlString) {
                    UIApplication.shared.open(url)
                }
                feed = nil
            }
            Button("稍后再说", role: .cancel) { feed = nil }
        } message: {
            Text(feed?.notes.isEmpty == false ? feed!.notes : "下载新包后去签名工具重签安装。")
        }
    }

    private func check() async {
        busy = true
        defer { busy = false }
        switch await UpdateChecker.check() {
        case .upToDate:
            status = "已经是最新"
        case .available(let f):
            feed = f
            status = "有新版本，点上面的弹窗去下载"
        case .unavailable(let reason):
            status = reason
        }
    }
}
