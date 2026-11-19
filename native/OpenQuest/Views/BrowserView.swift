import SwiftUI

/// 浏览器页显示的是**服务器上的浏览器**，不是手机内置的：
/// 输网址 → 服务器的浏览器打开 → 把截图和正文回传，App 只负责显示。
/// 手机是窗口，浏览器本体在服务器上跑。
struct BrowserView: View {
    @EnvironmentObject var store: AppStore
    @State private var urlText = ""
    @State private var title = ""
    @State private var text = ""
    @State private var screenshot: UIImage?
    @State private var status: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("输入网址，服务器浏览器打开", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .onSubmit { Task { await open() } }
                Button("打开") { Task { await open() } }
            }
            .padding(8)
            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.bottom, 6)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !title.isEmpty {
                        Text(title).font(.headline)
                    }
                    if let shot = screenshot {
                        // 显示的是服务器浏览器的画面；点画面 = 在服务器浏览器里点那个位置。
                        GeometryReader { geo in
                            Image(uiImage: shot)
                                .resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { pt in
                                    let x = pt.x / geo.size.width
                                    let y = pt.y / geo.size.height
                                    Task { await act(["type": "click", "x": x, "y": y]) }
                                }
                        }
                        .aspectRatio(shot.size.width / shot.size.height, contentMode: .fit)
                        Button("刷新画面") { Task { await act(["type": "screenshot"]) } }
                    }
                    if !text.isEmpty {
                        Text(text).font(.callout).foregroundStyle(.secondary)
                    }
                    if title.isEmpty && screenshot == nil && status == nil {
                        Text("还没打开网页。上面输个网址，服务器的浏览器会打开它，你看到的是它那边的画面。")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
            }
        }
        .navigationTitle("服务器浏览器")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func open() async {
        var t = urlText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        if !t.hasPrefix("http") { t = "https://" + t }
        await act(["type": "navigate", "url": t])
    }

    private func act(_ action: [String: Any]) async {
        status = "服务器浏览器操作中…"
        do {
            let r = try await ServerClient(config: store.server)
                .browserAction(agentId: "user", action: action)
            title = r.title
            text = r.text
            if let b64 = r.screenshotBase64, let data = Data(base64Encoded: b64) {
                screenshot = UIImage(data: data)
            }
            status = nil
        } catch {
            status = "失败：\(error.localizedDescription)（先在设置里填好服务器令牌）"
        }
    }
}
