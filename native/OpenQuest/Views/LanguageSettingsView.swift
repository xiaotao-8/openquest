import SwiftUI

/// 语言设置：六种语言，换了立即生效（核心界面字符串走 L10n 表）。
struct LanguageSettingsView: View {
    @EnvironmentObject var store: AppStore
    private func L(_ key: String) -> String { L10n.t(key, lang: store.language) }

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
                Text(L("lang_footnote"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L("language"))
    }
}

/// 用量统计：全部会话的回复用量合计 + 按智能体分。
struct UsageStatsView: View {
    @EnvironmentObject var store: AppStore
    private func L(_ key: String) -> String { L10n.t(key, lang: store.language) }

    var body: some View {
        List {
            Section(L("total")) {
                HStack {
                    Text(L("input_tokens"))
                    Spacer()
                    Text("\(store.totalUsage.prompt) tokens")
                }
                HStack {
                    Text(L("output_tokens"))
                    Spacer()
                    Text("\(store.totalUsage.completion) tokens")
                }
                HStack {
                    Text(L("grand_total"))
                    Spacer()
                    Text("\(store.totalUsage.prompt + store.totalUsage.completion) tokens")
                        .font(.body.weight(.semibold))
                }
            }
            Section(L("usage_by_agent")) {
                if store.usageByAgent().isEmpty {
                    Text(L("usage_empty"))
                        .foregroundStyle(.secondary)
                }
                ForEach(store.usageByAgent(), id: \.name) { row in
                    HStack {
                        Text(row.name)
                        Spacer()
                        Text(String(format: L("usage_in_out_fmt"), row.prompt, row.completion))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Text(L("usage_note"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L("usage"))
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
