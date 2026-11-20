import SwiftUI

/// 小工具 MiniApps（FishPocket 式）：应用 = 一个文件夹（app.json + 页面文件），
/// 存在 App 数据里，WKWebView 用 miniapp:// 自定义协议跑起来。
/// 列表 + 新建 + 点进去改文件（改完保存再跑就生效）。
struct MiniAppsView: View {
    @EnvironmentObject var store: AppStore
    @State private var showingAdd = false

    var body: some View {
        List {
            if store.miniApps.isEmpty {
                Text("还没有小工具。新建一个：给它起个名字，就会生成一个能直接跑的网页小工具，点进去还能改它的文件。")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.miniApps) { app in
                NavigationLink {
                    MiniAppDetailView(app: app)
                } label: {
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
    }
}

/// 小工具详情：跑起来 + 改文件。app.json 里有 entry 就用它，没有默认 index.html。
private struct MiniAppDetailView: View {
    @EnvironmentObject var store: AppStore
    let app: MiniApp
    @State private var running = false
    @State private var editingFile: String?
    @State private var newFileName = ""
    @State private var showingAddFile = false

    private var current: MiniApp? { store.miniApps.first { $0.id == app.id } }

    var body: some View {
        List {
            Section {
                Button { running = true } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("运行这个小工具")
                    }
                }
            }
            Section("文件") {
                if let current {
                    ForEach(current.files.keys.sorted(), id: \.self) { name in
                        HStack {
                            Text(name)
                            Spacer()
                            Text("\((current.files[name] ?? "").count) 字")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("改") { editingFile = name }
                                .font(.subheadline)
                        }
                    }
                    .onDelete { idx in
                        for i in idx {
                            let name = current.files.keys.sorted()[i]
                            // index.html 和 app.json 删了就跑不起来，这里拦住。
                            if name == "index.html" || name == "app.json" { continue }
                            store.deleteMiniAppFile(id: app.id, file: name)
                        }
                    }
                    Button("加一个文件") { showingAddFile = true }
                }
            }
            Section {
                Text("文件存在 App 自己的数据里，WKWebView 用 miniapp:// 协议跑，不走网络。改完保存，下次运行就生效。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(app.name)
        .sheet(isPresented: $running) {
            NavigationStack {
                MiniAppWebView(app: current ?? app)
                    .navigationTitle(app.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("关闭") { running = false }
                        }
                    }
            }
        }
        .sheet(item: Binding(
            get: { editingFile.map { EditFileSheet(appId: app.id, file: $0) } },
            set: { if $0 == nil { editingFile = nil } }
        )) { sheet in
            NavigationStack {
                FileEditorView(appId: sheet.appId, file: sheet.file)
            }
        }
        .alert("加一个文件", isPresented: $showingAddFile) {
            TextField("文件名，如：about.html", text: $newFileName)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("加") {
                let name = newFileName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, (current?.files[name] == nil) else { return }
                store.updateMiniAppFile(id: app.id, file: name, content: "")
                newFileName = ""
                editingFile = name
            }
            Button("取消", role: .cancel) { newFileName = "" }
        } message: {
            Text("文件名要带后缀（.html / .js / .css / .json），加完直接进编辑。")
        }
    }

    private struct EditFileSheet: Identifiable {
        var id: String { appId.uuidString + "/" + file }
        let appId: UUID
        let file: String
    }
}

/// 改一个小工具文件：纯文本编辑，保存写回 App 数据。
private struct FileEditorView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let appId: UUID
    let file: String
    @State private var text = ""
    @State private var savedNote: String?

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(8)
            HStack {
                if let savedNote {
                    Text(savedNote).font(.caption).foregroundStyle(.green)
                }
                Spacer()
                Button("保存") {
                    store.updateMiniAppFile(id: appId, file: file, content: text)
                    savedNote = "已保存"
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .navigationTitle(file)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .onAppear {
            text = store.miniApps.first { $0.id == appId }?.files[file] ?? ""
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
                Text("新建会生成一个默认模板（app.json + index.html），跑起来就能看到效果。")
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
