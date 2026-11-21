import SwiftUI

/// Minimal read-only rendering of ```schemaJson blocks (FishPocket
/// GenUIView, reimplemented read-only): Page → TinyCard → Text /
/// TinyGrid / table. Charts render as a placeholder and interactive
/// components show the web notice — there is no native handler for
/// them. A block that does not parse falls back to the plain code
/// block, so a bad schema never breaks the message.
struct GenUIMessageView: View {
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(GenUIParser.segments(text).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let part):
                    if !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(markdown(part))
                            .font(.body)
                            .foregroundStyle(Palette.text)
                            .textSelection(.enabled)
                    }
                case .genUI(let node):
                    GenUIView(node: node)
                }
            }
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(markdown: text) { return attributed }
        return AttributedString(text)
    }
}

enum GenUISegment {
    case text(String)
    case genUI(JSONValue)
}

enum GenUIParser {
    /// Splits a message into plain-text parts and parsed schemaJson
    /// blocks. An unparseable or unterminated block stays a text part,
    /// so it renders exactly as before.
    static func segments(_ text: String) -> [GenUISegment] {
        var out: [GenUISegment] = []
        var currentLines: [String] = []
        var schemaLines: [String]? = nil
        func flushText() {
            let joined = currentLines.joined(separator: "\n")
            if !joined.isEmpty { out.append(.text(joined)) }
            currentLines = []
        }
        for line in text.components(separatedBy: "\n") {
            if schemaLines == nil {
                if line.trimmingCharacters(in: .whitespaces) == "```schemaJson" {
                    flushText()
                    schemaLines = []
                } else {
                    currentLines.append(line)
                }
            } else if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                let code = schemaLines!.joined(separator: "\n")
                if let node = parse(code) {
                    out.append(.genUI(node))
                } else {
                    out.append(.text("```schemaJson\n" + code + "\n```"))
                }
                schemaLines = nil
            } else {
                schemaLines!.append(line)
            }
        }
        if let open = schemaLines {
            out.append(.text("```schemaJson\n" + open.joined(separator: "\n")))
        }
        flushText()
        return out
    }

    /// A schemaJson block is one JSON object with a componentName.
    static func parse(_ code: String) -> JSONValue? {
        guard let data = code.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              value["componentName"].string != nil else { return nil }
        return value
    }
}

struct GenUIView: View {
    var node: JSONValue

    var body: some View {
        GenUINode(node: node)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GenUINode: View {
    var node: JSONValue

    private var name: String { node["componentName"].string ?? "" }
    private var props: JSONValue { node["props"] }

    var body: some View {
        switch name {
        case "Page", "div", "TinyLayout", "TinyRow", "TinyCol", "section", "Block":
            children(spacing: 10)
        case "TinyCard", "Card":
            VStack(alignment: .leading, spacing: 10) {
                if let title = props["title"].string {
                    Text(title).font(.headline).foregroundStyle(Palette.text)
                }
                children(spacing: 10)
            }
            .padding(14)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        case "h1", "h2", "h3", "h4", "h5", "h6":
            Text(text)
                .font(name == "h1" ? .title2.bold() : name == "h2" ? .title3.bold() : .headline)
                .foregroundStyle(Palette.text)
        case "Text", "span", "p", "TinyText", "label":
            Text(text)
                .font(.body)
                .foregroundStyle(Palette.text)
                .textSelection(.enabled)
        case "TinyGrid", "TinyTable", "Table":
            GenUITable(columns: props["columns"].array ?? [], rows: props["data"].array ?? [])
        case _ where name.hasPrefix("TinyHuicharts") || name.hasPrefix("TinyChart"):
            chartPlaceholder
        case "TinyTag", "Tag":
            Text(text)
                .font(.caption)
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Palette.bubbleAgent, in: Capsule())
        case "TinyDivider", "hr":
            Divider()
        case "img", "Image", "TinyImage":
            if let src = props["src"].string, let url = URL(string: src) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Spinner(size: 14)
                }
                .frame(maxHeight: 240)
            }
        case "TinyButton", "button", "TinyInput", "TinyForm", "TinySelect":
            Label(L("可交互内容 · 在网页版中操作"), systemImage: "hand.tap")
                .font(.caption)
                .foregroundStyle(Palette.secondary)
        default:
            if node["children"].array?.isEmpty == true, !text.isEmpty {
                Text(text).font(.body).foregroundStyle(Palette.text)
            } else {
                children(spacing: 8)
            }
        }
    }

    private var text: String {
        props["text"].string ?? node["children"].string ?? props["content"].string ?? ""
    }

    @ViewBuilder
    private func children(spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let text = node["children"].string {
                Text(text).font(.body).foregroundStyle(Palette.text)
            } else if let kids = node["children"].array {
                ForEach(Array(kids.enumerated()), id: \.offset) { _, child in
                    GenUINode(node: child)
                }
            }
        }
    }

    /// Charts have no native renderer in this build: title plus a
    /// placeholder note, never invented data.
    private var chartPlaceholder: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.system(size: 16))
                .foregroundStyle(Palette.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(props["options"]["title"]["text"].string ?? props["title"].string ?? L("图表"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.text)
                Text(L("图表暂以占位显示"))
                    .font(.caption)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct GenUITable: View {
    var columns: [JSONValue]
    var rows: [JSONValue]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        Text(column["title"].string ?? column["field"].string ?? "")
                            .font(.subheadline.bold())
                            .foregroundStyle(Palette.text)
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                            Text(cell(row[column["field"].string ?? ""]))
                                .font(.subheadline)
                                .foregroundStyle(Palette.text)
                        }
                    }
                }
            }
            .padding(10)
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func cell(_ value: JSONValue) -> String {
        if let string = value.string { return string }
        if let number = value.double { return number.rounded() == number ? String(Int(number)) : String(number) }
        if let bool = value.bool { return bool ? L("是") : L("否") }
        return ""
    }
}

private extension JSONValue {
    subscript(key: String) -> JSONValue {
        if case .object(let dict) = self { return dict[key] ?? .null }
        return .null
    }

    var array: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var double: Double? {
        switch self {
        case .int(let value): return Double(value)
        case .double(let value): return value
        default: return nil
        }
    }

    var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
}
