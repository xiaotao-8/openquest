import SwiftUI

/// 服务器设置：连用户自己的阿里云 ECS（智能体常驻主机，令牌鉴权）。
struct ServerView: View {
    @EnvironmentObject var store: AppStore
    @State private var token = ""
    @State private var testResult: String?

    var body: some View {
        Form {
            Section("服务器") {
                TextField("地址", text: $store.server.host)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                HStack {
                    Text("端口")
                    Spacer()
                    TextField("端口", value: $store.server.port, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                SecureField("访问令牌（存钥匙串）", text: $token)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            Section {
                Button("保存") {
                    if !token.isEmpty {
                        KeychainHelper.setKey(token, ref: store.server.tokenRef)
                    }
                    store.save()
                    testResult = "已保存"
                }
                Button("测试连接") { Task { await test() } }
                if let r = testResult {
                    Text(r).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("服务器")
        .onAppear {
            token = KeychainHelper.key(ref: store.server.tokenRef) ?? ""
        }
    }

    /// 通 = 能连到服务；401 说明服务在、只是令牌不对/没带；200 = 令牌正确。
    private func test() async {
        testResult = "测试中…"
        guard let url = URL(string: store.server.baseURL + "/health") else {
            testResult = "地址不对"
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        if let t = KeychainHelper.key(ref: store.server.tokenRef), !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            testResult = switch code {
            case 200: "连通了，令牌正确"
            case 401: "服务在，但令牌不对或没填"
            default: "服务回了 \(code)"
            }
        } catch {
            testResult = "连不上：\(error.localizedDescription)"
        }
    }
}
