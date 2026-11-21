import SwiftUI
import UIKit
import WebKit

/// The view card (FishPocket `show_view`, Phase 4, agent F): a native
/// render of the deep-view schema `{id, title, view}` — stack, row,
/// text, metric, table, chart, progress, callout, sources, html,
/// slider, number, choice, toggle, options, confirm, form, submit.
///
/// The card is at most 420pt tall and scrolls. Values may be formulas
/// `{"=": ...}` (only + - * / and field references); they recompute live
/// as the form inputs change, and a formula that cannot be computed
/// shows its source text, never a crash.
///
/// Host gap (probe 2026-11-22): codync-host 2.51.0 has no `view-reply`
/// or `dismiss-view` — both answer 404 "unknown method". So every
/// host-bound action (submit / confirm) is a disabled state with a
/// reason (§1.6.4); the inputs themselves are local-only and still work.
struct ViewCardView: View {
    var entry: Entry
    var bot: Bot
    @State private var values: [String: JSONValue]

    init(entry: Entry, bot: Bot) {
        self.entry = entry
        self.bot = bot
        let payload = entry.data.view
        _values = State(initialValue: payload.map { Self.initialValues(node: $0.view) } ?? [:])
    }

    private var payload: ViewCardPayload? { entry.data.view }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let payload {
                HStack(spacing: 8) {
                    Text(payload.title)
                        .font(.headline)
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)
                    Spacer()
                }
                ScrollView(showsIndicators: false) {
                    DeepViewBody(node: payload.view, values: $values)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 420)
            } else {
                Text(L("视图卡内容无法显示。"))
                    .font(.body)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Palette.bubbleAgent, in: RoundedRectangle(cornerRadius: 22))
        .padding(.trailing, 40)
    }

    /// Default form values, walked out of the view tree once: field
    /// defaults, pre-selected options, slider/number starts.
    static func initialValues(node: DeepViewNode) -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        collect(node: node, into: &out)
        return out
    }

    private static func collect(node: DeepViewNode, into out: inout [String: JSONValue]) {
        let key = node.label ?? node.title ?? node.type
        switch node.type {
        case "slider", "number":
            out[key] = node.value ?? .double(node.min ?? 0)
        case "toggle":
            out[key] = .bool(node.value?.asBool ?? false)
        case "choice":
            if let options = node.options, !options.isEmpty {
                let picked = options.first(where: { $0.selected }) ?? options[0]
                out[key] = .string(picked.id)
            }
        case "options":
            if let options = node.options {
                out[key] = .array(options.filter { $0.selected }.map { JSONValue.string($0.id) })
            }
        case "form":
            if let fields = node.fields {
                for field in fields {
                    collect(field: field, into: &out)
                }
            }
        default:
            break
        }
        if let children = node.children {
            for child in children { collect(node: child, into: &out) }
        }
    }

    private static func collect(field: DeepViewField, into out: inout [String: JSONValue]) {
        switch field.type {
        case "toggle":
            out[field.id] = .bool(field.value?.asBool ?? false)
        case "choice":
            if let options = field.options, !options.isEmpty {
                let picked = options.first(where: { $0.selected }) ?? options[0]
                out[field.id] = .string(picked.id)
            }
        case "options":
            if let options = field.options {
                out[field.id] = .array(options.filter { $0.selected }.map { JSONValue.string($0.id) })
            }
        case "slider", "number":
            out[field.id] = field.value ?? .double(field.min ?? 0)
        default:
            out[field.id] = field.value ?? .string("")
        }
    }
}

/// The disabled-state reason row (§1.6.4): grey text + a lock icon.
struct DisabledReasonLine: View {
    var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock")
                .font(.caption)
                .foregroundStyle(Palette.tertiary)
            Text(text)
                .font(.caption)
                .foregroundStyle(Palette.tertiary)
        }
    }
}

/// One deep-view node, rendered natively. Unknown types render as their
/// text when they have any, and as nothing otherwise — never a crash.
struct DeepViewBody: View {
    var node: DeepViewNode
    var values: Binding<[String: JSONValue]>

    var body: some View {
        switch node.type {
        case "stack":
            VStack(alignment: .leading, spacing: 10) {
                children
            }
        case "row":
            HStack(alignment: .top, spacing: 10) {
                children
            }
        case "text":
            Text(node.displayText(values: values.wrappedValue))
                .font(.body)
                .foregroundStyle(Palette.text)
                .textSelection(.enabled)
        case "metric":
            metric
        case "table":
            DeepViewTable(node: node)
        case "chart":
            DeepViewChart(node: node)
        case "progress":
            progress
        case "callout":
            callout
        case "sources":
            sources
        case "html":
            if let html = node.html, !html.isEmpty {
                HTMLBlockView(html: html)
            }
        case "slider":
            FormSliderRow(label: node.label ?? node.title ?? "", min: node.min, max: node.max,
                          step: node.step, value: sliderBinding(node))
        case "number":
            FormNumberRow(label: node.label ?? node.title ?? "", value: stringBinding(node))
        case "choice":
            FormChoiceRows(label: node.label ?? node.title, options: node.options ?? [],
                           selected: singleBinding(node))
        case "toggle":
            SwitchRow(label: node.label ?? node.title ?? "", detail: nil, isOn: boolBinding(node))
        case "options":
            FormOptionsRows(label: node.label ?? node.title, options: node.options ?? [],
                            selected: multiBinding(node))
        case "confirm":
            confirm
        case "form":
            VStack(alignment: .leading, spacing: 10) {
                if let fields = node.fields {
                    ForEach(fields) { field in
                        FormFieldRow(field: field, values: values)
                    }
                }
            }
        case "submit":
            submit
        default:
            if !(node.text ?? node.label ?? node.title ?? "").isEmpty {
                Text(node.text ?? node.label ?? node.title ?? "")
                    .font(.body)
                    .foregroundStyle(Palette.text)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var children: some View {
        if let children = node.children {
            ForEach(children.indices, id: \.self) { index in
                DeepViewBody(node: children[index], values: values)
            }
        }
    }

    private var metric: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let label = node.label ?? node.title {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Palette.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(node.displayText(values: values.wrappedValue))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.text)
                if let unit = node.unit, !unit.isEmpty {
                    Text(unit)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                }
            }
            if let detail = node.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Palette.secondary)
            }
        }
    }

    private var progress: some View {
        let raw = DeepViewValue.number(node.value, values: values.wrappedValue) ?? 0
        let fraction = min(max(raw > 1 ? raw / 100 : raw, 0), 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let label = node.label ?? node.title {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(Palette.text)
                }
                Spacer()
                Text("\(Int(fraction * 100))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Palette.secondary)
            }
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Palette.accentDim)
                    .frame(height: 8)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Palette.accentFill)
                            .frame(width: geometry.size.width * fraction, height: 8)
                    }
            }
            .frame(height: 8)
        }
    }

    private var callout: some View {
        let symbol: String
        switch node.tone {
        case "warning": symbol = "exclamationmark.triangle"
        case "error": symbol = "xmark.circle"
        default: symbol = "info.circle"
        }
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
            Text(node.displayText(values: values.wrappedValue))
                .font(.subheadline)
                .foregroundStyle(Palette.text)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("来源"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.secondary)
            if let sources = node.sources {
                ForEach(sources) { source in
                    if let urlString = source.url, let url = URL(string: urlString) {
                        Link(source.title.isEmpty ? urlString : source.title, destination: url)
                            .font(.subheadline)
                            .foregroundStyle(Palette.text)
                            .lineLimit(2)
                    } else {
                        Text(source.title)
                            .font(.subheadline)
                            .foregroundStyle(Palette.text)
                    }
                }
            }
        }
    }

    /// Confirm / cancel: both disabled — there is no host method to
    /// answer them with — with the reason underneath.
    private var confirm: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !(node.text ?? node.title ?? "").isEmpty {
                Text(node.text ?? node.title ?? "")
                    .font(.body)
                    .foregroundStyle(Palette.text)
            }
            HStack(spacing: 10) {
                Text(L("确认"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.onAccent)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Palette.accentFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .opacity(0.4)
                Text(L("取消"))
                    .font(.body)
                    .foregroundStyle(Palette.text)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .opacity(0.4)
            }
            .disabled(true)
            DisabledReasonLine(text: L("电脑暂不支持视图卡回复"))
        }
    }

    /// Submit: disabled — there is no host method to send the values
    /// to — with the reason underneath.
    private var submit: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(node.label ?? L("提交"))
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.onAccent)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Palette.accentFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .opacity(0.4)
                .disabled(true)
            DisabledReasonLine(text: L("电脑暂不支持视图卡回复"))
        }
    }

    // MARK: - Value bindings (keyed by label, else title, else type)

    private func nodeKey(_ node: DeepViewNode) -> String {
        node.label ?? node.title ?? node.type
    }

    private func stringBinding(_ node: DeepViewNode) -> Binding<String> {
        let key = nodeKey(node)
        let fallback = node.value?.asString ?? ""
        return Binding(
            get: { values.wrappedValue[key]?.asString ?? fallback },
            set: { values.wrappedValue[key] = .string($0) }
        )
    }

    private func boolBinding(_ node: DeepViewNode) -> Binding<Bool> {
        let key = nodeKey(node)
        let fallback = node.value?.asBool ?? false
        return Binding(
            get: { values.wrappedValue[key]?.asBool ?? fallback },
            set: { values.wrappedValue[key] = .bool($0) }
        )
    }

    private func sliderBinding(_ node: DeepViewNode) -> Binding<Double> {
        let key = nodeKey(node)
        let fallback = node.value?.asDouble ?? node.min ?? 0
        return Binding(
            get: { values.wrappedValue[key]?.asDouble ?? fallback },
            set: { values.wrappedValue[key] = .double($0) }
        )
    }

    private func singleBinding(_ node: DeepViewNode) -> Binding<String> {
        let key = nodeKey(node)
        let fallback = node.options?.first(where: { $0.selected })?.id ?? node.options?.first?.id ?? ""
        return Binding(
            get: { values.wrappedValue[key]?.asString ?? fallback },
            set: { values.wrappedValue[key] = .string($0) }
        )
    }

    private func multiBinding(_ node: DeepViewNode) -> Binding<Set<String>> {
        let key = nodeKey(node)
        let fallback = Set((node.options ?? []).filter { $0.selected }.map { $0.id })
        return Binding(
            get: {
                Set(values.wrappedValue[key]?.asArray?.compactMap { $0.asString } ?? fallback)
            },
            set: { values.wrappedValue[key] = .array($0.sorted().map { JSONValue.string($0) }) }
        )
    }
}

// MARK: - Form fields

/// One field of a `form` node, by its own type. Read-only fields show
/// as plain text; editable text fields cap at 2000 characters.
struct FormFieldRow: View {
    var field: DeepViewField
    var values: Binding<[String: JSONValue]>

    var body: some View {
        if field.readonly {
            VStack(alignment: .leading, spacing: 2) {
                if !field.label.isEmpty {
                    Text(field.label)
                        .font(.caption)
                        .foregroundStyle(Palette.secondary)
                }
                Text(field.value?.asString ?? "")
                    .font(.body)
                    .foregroundStyle(Palette.text)
                    .textSelection(.enabled)
                Text(L("只读"))
                    .font(.caption)
                    .foregroundStyle(Palette.tertiary)
            }
        } else {
            switch field.type {
            case "slider":
                FormSliderRow(label: field.label, min: field.min, max: field.max,
                              step: field.step, value: sliderBinding)
            case "number":
                FormNumberRow(label: field.label, value: stringBinding)
            case "choice":
                FormChoiceRows(label: field.label, options: field.options ?? [],
                               selected: singleBinding)
            case "toggle":
                SwitchRow(label: field.label, detail: nil, isOn: boolBinding)
            case "options":
                FormOptionsRows(label: field.label, options: field.options ?? [],
                                selected: multiBinding)
            default:
                FormTextRow(field: field, value: stringBinding)
            }
        }
    }

    private var stringBinding: Binding<String> {
        let fallback = field.value?.asString ?? ""
        return Binding(
            get: { values.wrappedValue[field.id]?.asString ?? fallback },
            set: { values.wrappedValue[field.id] = .string($0) }
        )
    }

    private var boolBinding: Binding<Bool> {
        let fallback = field.value?.asBool ?? false
        return Binding(
            get: { values.wrappedValue[field.id]?.asBool ?? fallback },
            set: { values.wrappedValue[field.id] = .bool($0) }
        )
    }

    private var sliderBinding: Binding<Double> {
        let fallback = field.value?.asDouble ?? field.min ?? 0
        return Binding(
            get: { values.wrappedValue[field.id]?.asDouble ?? fallback },
            set: { values.wrappedValue[field.id] = .double($0) }
        )
    }

    private var singleBinding: Binding<String> {
        let fallback = field.options?.first(where: { $0.selected })?.id ?? field.options?.first?.id ?? ""
        return Binding(
            get: { values.wrappedValue[field.id]?.asString ?? fallback },
            set: { values.wrappedValue[field.id] = .string($0) }
        )
    }

    private var multiBinding: Binding<Set<String>> {
        let fallback = Set((field.options ?? []).filter { $0.selected }.map { $0.id })
        return Binding(
            get: {
                Set(values.wrappedValue[field.id]?.asArray?.compactMap { $0.asString } ?? fallback)
            },
            set: { values.wrappedValue[field.id] = .array($0.sorted().map { JSONValue.string($0) }) }
        )
    }
}

/// A text field with the 2000-character cap (§2.2): input past the cap
/// is trimmed, and the cap is shown under the field.
struct FormTextRow: View {
    var field: DeepViewField
    var value: Binding<String>
    @State private var text: String

    init(field: DeepViewField, value: Binding<String>) {
        self.field = field
        self.value = value
        _text = State(initialValue: value.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if field.multiline {
                TextField(field.placeholder ?? field.label, text: $text, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...6)
            } else {
                TextField(field.placeholder ?? field.label, text: $text)
                    .font(.body)
            }
            Text(L("最多 2000 字"))
                .font(.caption)
                .foregroundStyle(Palette.tertiary)
        }
        .onChange(of: text) { _, newValue in
            let capped = String(newValue.prefix(2000))
            if capped != newValue { text = capped }
            value.wrappedValue = capped
        }
    }
}

/// A slider row: label, the slider, and the current value.
struct FormSliderRow: View {
    var label: String
    var min: Double?
    var max: Double?
    var step: Double?
    var value: Binding<Double>

    private var lower: Double { min ?? 0 }
    private var upper: Double { Swift.max(max ?? 100, lower) }
    private var stepValue: Double {
        let raw = step ?? 1
        return raw > 0 ? raw : 1
    }
    private var clamped: Binding<Double> {
        Binding(
            get: { Swift.min(Swift.max(value.wrappedValue, lower), upper) },
            set: { value.wrappedValue = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if !label.isEmpty {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(Palette.text)
                }
                Spacer()
                Text(DeepViewNumber.format(value.wrappedValue))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Palette.secondary)
            }
            Slider(value: clamped, in: lower...upper, step: stepValue)
        }
    }
}

/// A number row: label and a decimal-pad text field. Non-numeric input
/// stays as text (formulas then show their source); nothing crashes.
struct FormNumberRow: View {
    var label: String
    var value: Binding<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !label.isEmpty {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Palette.secondary)
            }
            TextField(label, text: value)
                .font(.body)
                .keyboardType(.decimalPad)
        }
    }
}

/// Single-choice rows: one tap picks; the picked row shows a filled dot.
struct FormChoiceRows: View {
    var label: String?
    var options: [DeepViewOption]
    var selected: Binding<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let label, !label.isEmpty {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Palette.secondary)
            }
            ForEach(options) { option in
                Button {
                    selected.wrappedValue = option.id
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selected.wrappedValue == option.id
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(Palette.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label)
                                .font(.body)
                                .foregroundStyle(Palette.text)
                            if let detail = option.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(Palette.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Multi-select rows: label + description line per option, tap to
/// toggle, checkmark on the picked rows.
struct FormOptionsRows: View {
    var label: String?
    var options: [DeepViewOption]
    var selected: Binding<Set<String>>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let label, !label.isEmpty {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Palette.secondary)
            }
            ForEach(options) { option in
                Button {
                    var next = selected.wrappedValue
                    if next.contains(option.id) { next.remove(option.id) } else { next.insert(option.id) }
                    selected.wrappedValue = next
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selected.wrappedValue.contains(option.id)
                              ? "checkmark.square.fill" : "square")
                            .foregroundStyle(Palette.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label)
                                .font(.body)
                                .foregroundStyle(Palette.text)
                            if let detail = option.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(Palette.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Table + chart

/// A table node: header row, scrollable rows, and a copy-as-TSV button.
struct DeepViewTable: View {
    var node: DeepViewNode
    @State private var copied = false

    private var columns: [String] { node.columns ?? [] }
    private var rows: [[JSONValue]] { node.rows ?? [] }

    private var tsv: String {
        var lines: [String] = []
        if !columns.isEmpty { lines.append(columns.joined(separator: "\t")) }
        for row in rows {
            lines.append(row.map { $0.asString ?? "" }.joined(separator: "\t"))
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let label = node.label ?? node.title {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button(copied ? L("已复制") : L("复制表格")) {
                    UIPasteboard.general.string = tsv
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        copied = false
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.secondary)
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    if !columns.isEmpty {
                        HStack(spacing: 16) {
                            ForEach(columns.indices, id: \.self) { index in
                                Text(columns[index])
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Palette.secondary)
                                    .frame(minWidth: 44, alignment: .leading)
                            }
                        }
                    }
                    ForEach(rows.indices, id: \.self) { rowIndex in
                        HStack(spacing: 16) {
                            ForEach(rows[rowIndex].indices, id: \.self) { colIndex in
                                Text(rows[rowIndex][colIndex].asString ?? "")
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.text)
                                    .frame(minWidth: 44, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// A chart node: line, bar and donut are drawn natively (180pt tall);
/// area / hbar and anything else show an unsupported line instead of a
/// wrong chart. Data can be copied as TSV.
struct DeepViewChart: View {
    var node: DeepViewNode
    @State private var copied = false

    /// The chart kind (`line` / `area` / `bar` / `hbar` / `donut`).
    private var kind: String { (node.kind ?? "bar").lowercased() }

    private var labels: [String] { node.labels ?? [] }
    private var series: [DeepViewSeries] { node.series ?? [] }

    private var tsv: String {
        var lines: [String] = []
        lines.append(([""] + series.map { $0.label }).joined(separator: "\t"))
        for index in labels.indices {
            let row = [labels[index]] + series.map { series in
                index < series.numbers.count ? DeepViewNumber.format(series.numbers[index]) : ""
            }
            lines.append(row.joined(separator: "\t"))
        }
        return lines.joined(separator: "\n")
    }

    private var palette: [Color] {
        Palette.avatarColors.map { $0.color }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let label = node.label ?? node.title {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
                if !series.isEmpty {
                    Button(copied ? L("已复制") : L("复制数据")) {
                        UIPasteboard.general.string = tsv
                        copied = true
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            copied = false
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.secondary)
                    .buttonStyle(.plain)
                }
            }
            if series.isEmpty {
                Text(L("暂无图表数据"))
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
            } else {
                switch kind {
                case "line":
                    DeepViewLineChart(labels: labels, series: series, palette: palette)
                        .frame(height: 180)
                case "bar":
                    DeepViewBarChart(labels: labels, series: series, palette: palette)
                        .frame(height: 180)
                case "donut":
                    DeepViewDonutChart(labels: labels, series: series, palette: palette)
                        .frame(height: 180)
                default:
                    Text(L("这种图表暂不支持显示"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                }
            }
        }
    }
}

/// A line chart: one polyline per series, dots on the points, x labels
/// along the bottom (up to 6, evenly spaced).
struct DeepViewLineChart: View {
    var labels: [String]
    var series: [DeepViewSeries]
    var palette: [Color]

    private var maxValue: Double {
        series.flatMap { $0.numbers }.max() ?? 0
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let count = max(labels.count, 1)
                let span = maxValue > 0 ? maxValue : 1
                ZStack {
                    ForEach(series.indices, id: \.self) { seriesIndex in
                        let numbers = series[seriesIndex].numbers
                        let points = numbers.indices.map { pointIndex -> CGPoint in
                            let x = count > 1
                                ? width * CGFloat(pointIndex) / CGFloat(count - 1)
                                : width / 2
                            let y = height - CGFloat(numbers[pointIndex] / span) * (height - 16) - 4
                            return CGPoint(x: x, y: y)
                        }
                        Path { path in
                            guard let first = points.first else { return }
                            path.move(to: first)
                            path.addLines(Array(points.dropFirst()))
                        }
                        .stroke(palette[seriesIndex % palette.count], lineWidth: 2)
                        ForEach(points.indices, id: \.self) { pointIndex in
                            Circle()
                                .fill(palette[seriesIndex % palette.count])
                                .frame(width: 6, height: 6)
                                .position(points[pointIndex])
                        }
                    }
                }
            }
            xLabels
        }
    }

    private var xLabels: some View {
        let shown = strideLabels
        return HStack {
            ForEach(shown.indices, id: \.self) { index in
                Text(shown[index].label)
                    .font(.caption2)
                    .foregroundStyle(Palette.tertiary)
                    .lineLimit(1)
                if index < shown.count - 1 { Spacer() }
            }
        }
    }

    /// At most 6 x labels, evenly spaced across the series.
    private var strideLabels: [(index: Int, label: String)] {
        guard !labels.isEmpty else { return [] }
        let step = max(1, (labels.count + 5) / 6)
        var out: [(Int, String)] = []
        var index = 0
        while index < labels.count {
            out.append((index, labels[index]))
            index += step
        }
        if let last = labels.indices.last, out.last?.0 != last {
            out.append((last, labels[last]))
        }
        return out
    }
}

/// A bar chart: one bar group per x label, one bar per series.
struct DeepViewBarChart: View {
    var labels: [String]
    var series: [DeepViewSeries]
    var palette: [Color]

    private var maxValue: Double {
        series.flatMap { $0.numbers }.max() ?? 0
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(labels.indices, id: \.self) { labelIndex in
                    VStack(spacing: 2) {
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(series.indices, id: \.self) { seriesIndex in
                                let numbers = series[seriesIndex].numbers
                                let value = labelIndex < numbers.count ? numbers[labelIndex] : 0
                                let span = maxValue > 0 ? maxValue : 1
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(palette[seriesIndex % palette.count])
                                    .frame(width: 14, height: max(2, CGFloat(value / span) * 128))
                            }
                        }
                        Text(labels[labelIndex])
                            .font(.caption2)
                            .foregroundStyle(Palette.tertiary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 156)
        }
    }
}

/// A donut chart: angular segments around a total in the middle, with a
/// legend underneath.
struct DeepViewDonutChart: View {
    var labels: [String]
    var series: [DeepViewSeries]
    var palette: [Color]

    private var segments: [(label: String, value: Double, color: Color)] {
        let numbers = series.first?.numbers ?? []
        return labels.indices.map { index in
            let value = index < numbers.count ? numbers[index] : 0
            return (labels[index], value, palette[index % palette.count])
        }
    }

    private var total: Double { segments.map { $0.value }.reduce(0, +) }

    private var ranges: [(start: Double, end: Double)] {
        var out: [(Double, Double)] = []
        var cursor = 0.0
        for segment in segments {
            let fraction = total > 0 ? segment.value / total : 0
            out.append((cursor, cursor + fraction))
            cursor += fraction
        }
        return out
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                ForEach(segments.indices, id: \.self) { index in
                    Circle()
                        .trim(from: CGFloat(ranges[index].start), to: CGFloat(ranges[index].end))
                        .stroke(segments[index].color, lineWidth: 26)
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 0) {
                    Text(L("总计"))
                        .font(.caption)
                        .foregroundStyle(Palette.secondary)
                    Text(DeepViewNumber.format(total))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Palette.text)
                }
            }
            .frame(width: 120, height: 120)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(segments.indices, id: \.self) { index in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(segments[index].color)
                            .frame(width: 8, height: 8)
                        Text(segments[index].label)
                            .font(.caption)
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                        Spacer()
                        Text(DeepViewNumber.format(segments[index].value))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - HTML block

/// An HTML block: rendered in a web view, at most 480pt tall, scrolling
/// inside the card when taller.
struct HTMLBlockView: View {
    var html: String
    @State private var height: CGFloat = 240

    var body: some View {
        HTMLWebView(html: html, height: $height)
            .frame(height: min(max(height, 120), 480))
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipped()
    }
}

private struct HTMLWebView: UIViewRepresentable {
    var html: String
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.loadHTMLString(html, baseURL: nil)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var height: Binding<CGFloat>

        init(height: Binding<CGFloat>) {
            self.height = height
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
                guard let self, let number = result as? NSNumber else { return }
                let measured = CGFloat(number.doubleValue)
                Task { @MainActor in
                    self.height.wrappedValue = measured
                }
            }
        }
    }
}
