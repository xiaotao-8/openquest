import Foundation
import SwiftUI
import WebKit

/// 小工具 MiniApp 的自定义协议：miniapp://<id>/index.html。
/// 文件存在 App 自己的数据里（MiniApp.files），WKWebView 用这个 handler 读出来跑，
/// 不走网络、不走文件系统。
final class MiniAppSchemeHandler: NSObject, WKURLSchemeHandler {
    var files: [String: String] = [:]

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "miniapp", code: 404))
            return
        }
        // miniapp://<id>/path/to/file → 取 path 部分的文件名。
        var path = url.path
        if path.hasPrefix("/") { path = String(path.dropFirst()) }
        if path.isEmpty { path = "index.html" }
        guard let content = files[path] else {
            urlSchemeTask.didFailWithError(NSError(domain: "miniapp", code: 404))
            return
        }
        let data = Data(content.utf8)
        let mime: String
        if path.hasSuffix(".html") { mime = "text/html" }
        else if path.hasSuffix(".js") { mime = "application/javascript" }
        else if path.hasSuffix(".css") { mime = "text/css" }
        else if path.hasSuffix(".json") { mime = "application/json" }
        else { mime = "text/plain" }
        let resp = URLResponse(url: url, mimeType: mime,
                               expectedContentLength: data.count, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(resp)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

/// 跑一个小工具的 WKWebView。
struct MiniAppWebView: UIViewRepresentable {
    let app: MiniApp

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let handler = MiniAppSchemeHandler()
        handler.files = app.files
        config.setURLSchemeHandler(handler, forURLScheme: "miniapp")
        let web = WKWebView(frame: .zero, configuration: config)
        // app.json 里有 entry 就用它，没有默认 index.html。
        var entry = "index.html"
        if let json = app.files["app.json"],
           let data = json.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let e = obj["entry"] as? String, !e.isEmpty {
            entry = e
        }
        if let url = URL(string: "miniapp://\(app.id.uuidString)/\(entry)") {
            web.load(URLRequest(url: url))
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// 新建小工具的默认模板：app.json + 一个能直接跑的 index.html。
enum MiniAppTemplate {
    static func files(name: String) -> [String: String] {
        [
            "app.json": """
            {
              "name": "\(name)",
              "entry": "index.html"
            }
            """,
            "index.html": """
            <!DOCTYPE html>
            <html lang="zh-CN">
            <head><meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>\(name)</title>
            <style>
              body { background: #fff; color: #0c0c0d; font-family: -apple-system, sans-serif;
                     margin: 0; padding: 24px; }
              h1 { font-size: 22px; }
              p { color: #6b6b72; line-height: 1.6; }
              button { background: #0c0c0d; color: #fff; border: 0; border-radius: 999px;
                       padding: 10px 22px; font-size: 16px; }
            </style></head>
            <body>
              <h1>\(name)</h1>
              <p>这是一个小工具的起点。改 index.html 就能改它。</p>
              <button onclick="document.getElementById('out').textContent = '你好，' + new Date().toLocaleTimeString()">点我</button>
              <p id="out"></p>
            </body>
            </html>
            """,
        ]
    }
}
