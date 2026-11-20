import SwiftUI
import WebKit

// MARK: - 回复分段：```html 与 ```mermaid 代码块直接渲染成卡片/图表，其余照常走行内 Markdown。

enum BodySegment {
    case text(String)
    case html(String)
    case mermaid(String)
}

/// 把回复切成文本 / HTML / Mermaid 三种段。没闭合的围栏当普通文本
/// （流式中途的半截块不渲染，等闭合再出现，避免边流边刷闪）。
func segments(of text: String) -> [BodySegment] {
    var out: [BodySegment] = []
    var textBuf = ""
    var codeBuf = ""
    var fence: String? = nil // "html" | "mermaid"

    func flushText() {
        if !textBuf.isEmpty {
            out.append(.text(textBuf))
            textBuf = ""
        }
    }

    for line in text.components(separatedBy: "\n") {
        if let f = fence {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                flushText()
                if f == "html" { out.append(.html(codeBuf)) }
                else { out.append(.mermaid(codeBuf)) }
                codeBuf = ""
                fence = nil
            } else {
                codeBuf += line + "\n"
            }
        } else if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            let lang = line.trimmingCharacters(in: .whitespaces)
                .dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased()
            if lang == "html" || lang == "mermaid" {
                fence = lang
                codeBuf = ""
            } else {
                textBuf += line + "\n"
            }
        } else {
            textBuf += line + "\n"
        }
    }
    if let f = fence {
        textBuf += "```\(f)\n" + codeBuf
    }
    flushText()
    return out
}

// MARK: - HTML 卡片 / Mermaid 图表

struct HTMLCardView: View {
    enum Kind { case html, mermaid }
    let code: String
    let kind: Kind
    @State private var height: CGFloat = 200
    @State private var showZoom = false

    var body: some View {
        HTMLWebView(html: document, height: $height)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Palette.stroke, lineWidth: 1))
            // 点开放大（DDchat 补 6）：HTML 卡片只放大，Mermaid 图表放大 + 可保存为图片。
            .overlay(alignment: .topTrailing) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .padding(6)
                    .background(Palette.background.opacity(0.9), in: Circle())
                    .padding(6)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture { showZoom = true }
            .fullScreenCover(isPresented: $showZoom) {
                ChartZoomView(code: code, kind: kind)
            }
    }

    private var document: String { Self.document(for: code, kind: kind) }

    /// 卡片文档（浅色，配 Palette；Mermaid 用打进包里的 mermaid.min.js 本地渲染，不依赖外网）。
    /// ChartZoomView 复用同一份文档，保证放大页和卡片看到的是同一张图。
    static func document(for code: String, kind: Kind) -> String {
        switch kind {
        case .html:
            return """
            <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
            <style>body{margin:0;padding:8px;background:#FFFFFF;color:#0C0C0D;font-family:-apple-system,BlinkMacSystemFont,sans-serif}</style>
            </head><body>\(code)</body></html>
            """
        case .mermaid:
            return """
            <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
            <style>body{margin:0;padding:8px;background:#FFFFFF;color:#0C0C0D;font-family:-apple-system,sans-serif}
            .mermaid{display:flex;justify-content:center}</style>
            <script src="mermaid.min.js"></script>
            </head><body><pre class="mermaid">\(escape(code))</pre>
            <script>mermaid.initialize({startOnLoad:true,theme:'default'});</script>
            </body></html>
            """
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// WKWebView 包装：内容变了才重载；载完量一次正文高度，卡片跟着长，
/// 内部不滚动，外层列表滚动。
/// onWebView 把建好的 WKWebView 交给调用方（放大页拿它截图保存）；卡片本身不用就传 nil。
struct HTMLWebView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat
    var onWebView: ((WKWebView) -> Void)? = nil

    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        wv.navigationDelegate = context.coordinator
        wv.scrollView.isScrollEnabled = false
        wv.isOpaque = false
        wv.backgroundColor = .clear
        onWebView?(wv)
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            wv.loadHTMLString(html, baseURL: Bundle.main.bundleURL)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML = ""
        var height: Binding<CGFloat>

        init(height: Binding<CGFloat>) { self.height = height }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
                guard let h = result as? Double, h > 0 else { return }
                Task { @MainActor in
                    self?.height.wrappedValue = min(max(h, 120), 640)
                }
            }
        }
    }
}
