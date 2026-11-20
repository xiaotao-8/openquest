import SwiftUI

/// LaTeX 公式渲染（DDchat 补 1）。
///
/// 商店原文：「支持 LaTeX 数学公式与 Mermaid 图表，在对话中清晰呈现公式、流程图、时序图等内容。」
/// 缺口核查（DDCHAT_SUPPLEMENT.md 补 1）：`segments(of:)` 只分 html / mermaid / text 三种段，
/// `$...$` / `$$...$$` 会当普通文本；全 App grep latex/katex/mathjax 零命中。
///
/// 做法：轻量原生方案，不依赖外网、不打 KaTeX 包（包里只有 mermaid.min.js，没有 KaTeX；
/// 下 KaTeX 全套字体文件重且要改打包清单，本轮不做）。行内公式转系统衬线斜体 +
/// 上下标近似渲染；不支持的命令原样显示命令名，不丢内容。
/// 支持：希腊字母（\alpha…\Omega）、^ 上标、_ 下标、\frac{a}{b}（写成 a⁄b）、\sqrt、
/// \pm \times \div \leq \geq \neq \approx \infty \sum \int 等常用符号。
/// 局限：复杂排版（矩阵、大括号分段函数、多行对齐）只作近似显示，不骗人说是全渲染。
///
/// ChatView 接入点（给协调员；不要改本文件以外的文件来接）：
/// ChatView.swift 约 1619–1631 行，消息正文渲染处 `case .text(let t): Text(attributed(t))`
/// 改成 `MessageRichTextView(text: t)` 即可；本文件内的 `messageAttributed(_:)` 与
/// ChatView 现有的 `attributed(_:)` 是同一实现，替换后 Markdown 行为不变。

// MARK: - 分段：文本 / 行内公式 / 展示公式

enum LaTeXSegment {
    case text(String)
    case inline(String)
    case display(String)
}

/// 把消息切成文本与公式段。认三种写法：```latex 围栏、$$...$$ 展示、$...$ 行内。
/// `\$` 是转义的美元符，不开公式；行内公式要求开闭在同一行，没闭合的当普通文本。
func latexSegments(of text: String) -> [LaTeXSegment] {
    var out: [LaTeXSegment] = []
    var buf = ""
    var i = text.startIndex

    func flushText() {
        if !buf.isEmpty { out.append(.text(buf)); buf = "" }
    }

    while i < text.endIndex {
        // 转义的 \$
        if text[i] == "\\", text.index(after: i) < text.endIndex,
           text[text.index(after: i)] == "$" {
            buf.append("$")
            i = text.index(i, offsetBy: 2)
            continue
        }
        // ```latex 围栏
        if text[i...].hasPrefix("```latex") {
            flushText()
            let afterFence = text.index(i, offsetBy: "```latex".count)
            if let close = text[afterFence...].range(of: "```") {
                let formula = String(text[afterFence..<close.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                out.append(.display(formula))
                i = close.upperBound
                continue
            }
            buf.append("```latex")
            i = afterFence
            continue
        }
        // $$...$$ 展示公式（可跨行）
        if text[i...].hasPrefix("$$") {
            let afterOpen = text.index(i, offsetBy: 2)
            if let close = text[afterOpen...].range(of: "$$") {
                flushText()
                out.append(.display(String(text[afterOpen..<close.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)))
                i = close.upperBound
                continue
            }
            buf.append("$$")
            i = afterOpen
            continue
        }
        // $...$ 行内公式（同一行内找闭合）
        if text[i] == "$" {
            let afterOpen = text.index(after: i)
            var j = afterOpen
            var closed: String.Index? = nil
            while j < text.endIndex {
                if text[j] == "\n" { break }
                if text[j] == "$" { closed = j; break }
                j = text.index(after: j)
            }
            if let c = closed, c > afterOpen {
                flushText()
                out.append(.inline(String(text[afterOpen..<c])))
                i = text.index(after: c)
                continue
            }
            buf.append("$")
            i = afterOpen
            continue
        }
        buf.append(text[i])
        i = text.index(after: i)
    }
    flushText()
    return out
}

// MARK: - 公式 → AttributedString（衬线斜体 + 上下标）

enum LaTeXRenderer {
    private static let symbols: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε",
        "zeta": "ζ", "eta": "η", "theta": "θ", "iota": "ι", "kappa": "κ",
        "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π",
        "rho": "ρ", "sigma": "σ", "tau": "τ", "upsilon": "υ", "phi": "φ",
        "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ",
        "Pi": "Π", "Sigma": "Σ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        "pm": "±", "mp": "∓", "times": "×", "div": "÷", "cdot": "·",
        "leq": "≤", "geq": "≥", "neq": "≠", "approx": "≈", "equiv": "≡",
        "infty": "∞", "partial": "∂", "sum": "∑", "prod": "∏", "int": "∫",
        "sqrt": "√", "to": "→", "Rightarrow": "⇒", "Leftarrow": "⇐",
        "Leftrightarrow": "⇔", "in": "∈", "notin": "∉", "cup": "∪", "cap": "∩",
        "subset": "⊂", "supset": "⊃", "circ": "∘", "ast": "∗", "oplus": "⊕",
        "otimes": "⊗", "perp": "⊥", "angle": "∠", "triangle": "△",
        "nabla": "∇", "hbar": "ℏ", "ldots": "…", "cdots": "⋯", "forall": "∀",
        "exists": "∃", "emptyset": "∅", "propto": "∝", "sim": "∼", "cong": "≅",
    ]

    /// 公式解析成带样式的 AttributedString。baseSize 是正文字号，上标/下标按比例缩小并抬高/压低。
    static func attributed(_ formula: String, baseSize: CGFloat = 17) -> AttributedString {
        var out = AttributedString()
        let chars = Array(formula)
        var i = 0

        func baseAttrs() -> AttributeContainer {
            var c = AttributeContainer()
            c.font = Font.system(size: baseSize, design: .serif).italic()
            return c
        }
        func scriptAttrs(up: Bool) -> AttributeContainer {
            var c = AttributeContainer()
            c.font = Font.system(size: baseSize * 0.72, design: .serif).italic()
            c.baselineOffset = up ? baseSize * 0.38 : -baseSize * 0.22
            return c
        }
        func append(_ s: String, attrs: AttributeContainer) {
            guard !s.isEmpty else { return }
            out.append(AttributedString(s, attributes: attrs))
        }

        // 读一个“原子”：{...} 分组、\命令、或单个字符。返回（文本，是否命令）。
        func readAtom(_ start: Int) -> (String, Int) {
            guard start < chars.count else { return ("", start) }
            if chars[start] == "{" {
                var depth = 0
                var j = start
                while j < chars.count {
                    if chars[j] == "{" { depth += 1 }
                    if chars[j] == "}" {
                        depth -= 1
                        if depth == 0 { return (String(chars[(start + 1)..<j]), j + 1) }
                    }
                    j += 1
                }
                return (String(chars[(start + 1)...]), chars.count)
            }
            if chars[start] == "\\" {
                var j = start + 1
                var name = ""
                while j < chars.count, chars[j].isLetter {
                    name.append(chars[j])
                    j += 1
                }
                if name.isEmpty, j < chars.count {
                    // \% \{ \} 等单字符转义
                    return (String(chars[j]), j + 1)
                }
                return ("\\" + name, j)
            }
            return (String(chars[start]), start + 1)
        }

        func renderCommand(_ name: String) -> String {
            symbols[name] ?? "\\" + name
        }

        while i < chars.count {
            let ch = chars[i]
            if ch == "\\" {
                let (atom, next) = readAtom(i)
                let name = String(atom.dropFirst())
                if name == "frac" {
                    // \frac{a}{b} → a⁄b
                    let (num, n1) = readAtom(next)
                    let (den, n2) = readAtom(n1)
                    append("\(num)⁄\(den)", attrs: baseAttrs())
                    i = n2
                    continue
                }
                if name == "sqrt" {
                    let (inner, n1) = readAtom(next)
                    append("√\(inner)", attrs: baseAttrs())
                    i = n1
                    continue
                }
                if name == "left" || name == "right" {
                    // \left( \right) 只留括号本身
                    let (delim, n1) = readAtom(next)
                    append(delim, attrs: baseAttrs())
                    i = n1
                    continue
                }
                if name == "text" || name == "mathrm" {
                    let (inner, n1) = readAtom(next)
                    append(inner, attrs: baseAttrs())
                    i = n1
                    continue
                }
                append(renderCommand(name), attrs: baseAttrs())
                i = next
                continue
            }
            if ch == "^" || ch == "_" {
                let up = ch == "^"
                let (atom, next) = readAtom(i + 1)
                // 原子里的命令也要展开（如 x^{\alpha}）
                let rendered: String
                if atom.hasPrefix("\\") {
                    rendered = renderCommand(String(atom.dropFirst()))
                } else {
                    rendered = atom
                }
                append(rendered, attrs: scriptAttrs(up: up))
                i = next
                continue
            }
            if ch == "{" || ch == "}" {
                // 裸分组括号不显示，只起分组作用
                i += 1
                continue
            }
            append(String(ch), attrs: baseAttrs())
            i += 1
        }
        return out
    }
}

// MARK: - 公式视图

struct LaTeXView: View {
    let formula: String
    var display = false

    var body: some View {
        if display {
            Text(LaTeXRenderer.attributed(formula))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Palette.field, in: RoundedRectangle(cornerRadius: 10))
        } else {
            Text(LaTeXRenderer.attributed(formula))
        }
    }
}

// MARK: - 消息富文本渲染入口（ChatView 接这里；见文件头接入点说明）

/// 与 ChatView 现有的 `attributed(_:)` 同一实现：行内 Markdown。
func messageAttributed(_ s: String) -> AttributedString {
    (try? AttributedString(
        markdown: s,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    )) ?? AttributedString(s)
}

/// 一条消息的完整渲染：文本段走 Markdown，行内公式拼进同一段落，展示公式单独成块居中。
/// ChatView 里把 `Text(attributed(t))` 换成 `MessageRichTextView(text: t)` 即可接入。
struct MessageRichTextView: View {
    let text: String

    private enum Block {
        case paragraph(AttributedString)
        case display(String)
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var para = AttributedString()
        func flushPara() {
            if !para.characters.isEmpty { out.append(.paragraph(para)); para = AttributedString() }
        }
        for seg in latexSegments(of: text) {
            switch seg {
            case .text(let t):
                para.append(messageAttributed(t))
            case .inline(let f):
                para.append(LaTeXRenderer.attributed(f))
            case .display(let f):
                flushPara()
                out.append(.display(f))
            }
        }
        flushPara()
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let attr):
                    Text(attr)
                        .font(.body)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .display(let f):
                    LaTeXView(formula: f, display: true)
                }
            }
        }
    }
}
