import SwiftUI

/// Cordis 面板：DSH 的动态插件系统里，智能体在运行时定义的插件。
///
/// 定论（2026-11-22，G worker）：Cordis 要真跑需要 DSH 引擎，而
/// codync-host 没有 DSH 引擎。证据：codync-host 2.51.0 二进制里
/// `cordis` / `dynamicCordis` / `dsh-client` 零命中，host 自己的
/// 仓库源码里也没有；host 只提供 ACP 智能体，没有动态插件的
/// inventory / runHostHalf / stop / undefine 接口。所以这页是诚实
/// 空态：没有运行体，运行/停止/删除/重试/回滚全部禁用态，并写明
/// 原因。接上 DSH 引擎之前，任何“在跑”的显示都是假的。
///
/// Host 半与 Client 半（按 FishPocket 的分界）：插件的 Host 半在
/// 引擎里跑，Client 半是网页界面，App 里跑不了。凡是需要 Client
/// 半的请求，在 FishPocket 里会立即拒绝（原因码
/// `client-half-failed`），以免智能体的回合卡在等一个不存在的
/// 页面；我们的面板同样写明这条规则。
struct CordisPanelView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("Cordis 动态插件")) {
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DisabledCard(
                        title: L("还没有 Cordis 运行体"),
                        detail: L("这台电脑没有 DSH 引擎，Cordis 动态插件无法运行。"))
                    CardSection(title: L("当前会话")) {
                        CardRow {
                            Text(L("没有运行体"))
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    CardSection(title: L("其他会话")) {
                        CardRow {
                            Text(L("没有运行体"))
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    CardSection(title: L("操作")) {
                        CardRow {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    actionButton(L("运行"))
                                    actionButton(L("停止"))
                                    actionButton(L("删除"))
                                    actionButton(L("重试"))
                                    actionButton(L("回滚"))
                                }
                                Text(L("未连接 DSH 引擎"))
                                    .font(.caption)
                                    .foregroundStyle(Palette.secondary)
                            }
                        }
                    }
                    DisabledCard(
                        title: L("Host 半与 Client 半"),
                        detail: L("Cordis 是 DSH 的动态插件系统：插件的 Host 半在引擎里跑，Client 半是网页界面，App 里只能跑 Host 半。需要网页界面的请求会被立即拒绝，不会让智能体一直等一个打不开的页面。要真跑 Cordis，需要 DSH 引擎，这台电脑上没有。"))
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .background(Palette.background)
    }

    /// An action that cannot run without an engine: visible, but
    /// honestly disabled, with the reason shown under the row.
    private func actionButton(_ label: String) -> some View {
        Button(label) {}
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(Palette.secondary)
            .disabled(true)
            .opacity(0.4)
    }
}
