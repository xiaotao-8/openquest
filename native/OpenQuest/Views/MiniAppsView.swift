import SwiftUI

/// 小工具 MiniApps（FishPocket 式）：应用 = 一个文件夹（app.json + 页面文件），
/// 存在 App 数据里，WKWebView 用 miniapp:// 自定义协议跑起来。列表 + 新建。
struct MiniAppsView: View {
    @EnvironmentObject var store: AppStore
    @State private var showingAdd = false
    @State private var running: MiniApp?

    var body: some View {
        List {
            if store.miniApps.isEmpty {
                Text("还没有小工具。新建一个：给它起个名字，就会生成一个能直接跑的网页小工具（改 index.html 就能改它）。")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.miniApps) { app in
                Button { running = app } label: {
                    HStack {
                        Image(systemName: "square.on.circle")
                            .frame(width: 34, height: 34)
                            .liquidGlass(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name).foregroundStyle(.primary)
                            Text("\(app.files.count) 个文件")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "play.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { idx in
                for i in idx { store.deleteMiniApp(id: store.miniApps[i].id) }
            }
        }
        .navigationTitle("小工具")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) { AddMiniAppView() }
        .sheet(item: $running) { app in
            NavigationStack {
                MiniAppWebView(app: app)
                    .navigationTitle(app.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("关闭") { running = nil }
                        }
                    }
            }
        }
    }
}

private struct AddMiniAppView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("小工具名字，如：倒计时", text: $name)
                Text("新建会生成一个默认模板（app.json + index.html），跑起来就能看到效果；想改就改它的页面文件。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("新建小工具")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        store.addMiniApp(name: n, files: MiniAppTemplate.files(name: n))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
