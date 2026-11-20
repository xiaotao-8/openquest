import Foundation

/// 云更新（用户原要求）：版本源 feed 在 ECS 上，App 每次打开查一次，
/// 有新版就弹窗提示下载；下载后跳转签名工具重签安装（免费签名下这一步绕不开，
/// 目标是最接近直接更新的形态）。界面里不显示版本号，只比对、不展示。
enum UpdateChecker {
    struct Feed: Decodable {
        var version: String = ""
        var build: Int = 0
        var url: String = ""
        var notes: String = ""
    }

    enum Result {
        case upToDate
        case available(Feed)
        case unavailable(String)
    }

    /// 当前 build（Info.plist 里的 CFBundleVersion，内部比对用，不显示）。
    static var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1") ?? 1
    }

    static var feedURL: String { "http://47.238.160.204:8080/version.json" }

    static func check() async -> Result {
        guard let url = URL(string: feedURL) else { return .unavailable("版本源地址不对") }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        do {
            let (data, resp) = try await Net.session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { return .unavailable("版本源还没建好（\(code)）") }
            let feed = try JSONDecoder().decode(Feed.self, from: data)
            if feed.build > currentBuild, !feed.url.isEmpty {
                return .available(feed)
            }
            return .upToDate
        } catch {
            return .unavailable("查不到版本源：\(error.localizedDescription)")
        }
    }
}
