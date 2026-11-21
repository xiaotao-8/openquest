import SwiftUI

/// Reporting a market item (connector or skill).
///
/// There is no report service in this deployment: codync-host exposes
/// no report endpoint and no takedown list (checked against the
/// 2.51.0 host: zero hits for a report endpoint or a takedown list in
/// the host binary, and none in the host's own repo). The sheet
/// therefore shows what a report would contain, and the submit button
/// stays honestly disabled — nothing is ever sent to an address that
/// does not exist, and no fake "submitted" state is shown. When a
/// report service is connected, this is the place to wire the real
/// submit; until then the takedown section is not shown anywhere.
enum PluginReportCategory: String, CaseIterable, Identifiable {
    case illegal, malicious, privacy, impersonation, broken, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .illegal: L("违法和不良信息")
        case .malicious: L("恶意代码与权限滥用")
        case .privacy: L("隐私与数据采集")
        case .impersonation: L("冒充与侵权")
        case .broken: L("失效与崩溃")
        case .other: L("其他")
        }
    }

    var detail: String {
        switch self {
        case .illegal: L("名称、介绍或内容含违法、色情、暴力等信息")
        case .malicious: L("偷偷做与介绍不符的事，或越权访问")
        case .privacy: L("未经同意收集或上传数据")
        case .impersonation: L("冒用他人名义或侵犯版权")
        case .broken: L("装不上、用不了或导致崩溃")
        case .other: L("以上都不是")
        }
    }
}

/// The report sheet: category + description, with the submit button
/// disabled because no report service is connected. The filled-in
/// content stays on this device; nothing leaves it.
struct PluginReportSheet: View {
    var name: String
    var version: String?
    @Environment(\.dismiss) private var dismiss
    @State private var category: PluginReportCategory?
    @State private var description = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("举报")) {
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                        if let version, !version.isEmpty {
                            Text(version)
                                .font(.footnote.monospaced())
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    CardSection(title: L("问题类型")) {
                        ForEach(PluginReportCategory.allCases) { option in
                            CardRow {
                                Button {
                                    category = option
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(option.title)
                                                .foregroundStyle(Palette.text)
                                            Text(option.detail)
                                                .font(.caption)
                                                .foregroundStyle(Palette.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        if category == option {
                                            Image(systemName: "checkmark")
                                                .font(.callout.weight(.semibold))
                                                .foregroundStyle(Palette.text)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            if option != PluginReportCategory.allCases.last { Hairline() }
                        }
                    }
                    CardSection(title: L("问题描述")) {
                        CardRow {
                            TextField(L("说明你看到了什么、在哪里看到的"), text: $description, axis: .vertical)
                                .lineLimit(4...10)
                                .focused($focused)
                                .font(.body)
                        }
                    }
                    DisabledCard(
                        title: L("举报服务未接通"),
                        detail: L("这台电脑没有接举报服务，举报发不出去。填好的内容只留在这台设备上，不会发出去。"))
                    PrimaryActionButton(title: L("举报服务未接通"), isEnabled: false) {}
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .background(Palette.background)
    }
}
