import SwiftUI

/// 电脑操作 (computer use): the 16 tools a bot can drive a desktop with.
///
/// Honest state page only — nothing here pretends to operate a computer.
/// Evidence (2026-11-22):
/// - Host source has the tools (`host/src/screen/cua_tools.json`, 16 tools;
///   `computer.rs` / `cua.rs`): the cua-driver runs beside the host on
///   macOS / Windows, and on Linux only with an X11 or Sway session, else
///   the portal-input helper tools (screenshot / ui_tree / click / move /
///   drag / scroll / type / key, via the remote-screen helper).
/// - Live probe (probe_p4h.py, host 2.51.0): `computerTools` answers 403
///   "This can only be done at the computer itself." — the phone cannot
///   call it at all, and a bot's `computer` switch must be on for it.
/// - ECS check (ssh, same day): no DISPLAY, session type tty,
///   `/tmp/.X11-unix` empty, no Xvfb / Xorg, no desktop process; the
///   cua-driver binary is present beside the host but there is no desktop
///   for it to drive. So on this server computer use is unavailable.
/// What it would take on a desktop computer is listed at the bottom.
struct ComputerUseView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("电脑操作")) {
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusSection
                    toolsSection
                    helperSection
                    neededSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(Palette.background)
    }

    private var statusSection: some View {
        CardSection(title: L("状态")) {
            CardRow {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle().fill(Palette.tertiary).frame(width: 10, height: 10)
                        Text(L("不可用"))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.text)
                    }
                    Text(L("这台电脑没有可操作的桌面：主机跑在无界面的服务器上，没有显示器画面，操作工具没有可点的东西。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("手机也调不到主机的电脑操作接口：主机只接受本机调用，手机调用会被拒绝。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var toolsSection: some View {
        CardSection(
            title: L("16 个操作工具"),
            footer: L("只读的工具只看不改；会改动的工具要点按、打字、改值，须先有人在电脑上开好远程屏幕并给智能体开电脑操作开关。")
        ) {
            ForEach(ComputerUseTools.all, id: \.name) { tool in
                if tool.name != ComputerUseTools.all.first?.name {
                    Hairline()
                }
                CardRow {
                    HStack {
                        Text(tool.name)
                            .font(.body.monospaced())
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Text(tool.readOnly ? L("只读") : L("会改动"))
                            .font(.subheadline)
                            .foregroundStyle(tool.readOnly ? Palette.secondary : Palette.attention)
                        Text(L("不可用"))
                            .font(.subheadline)
                            .foregroundStyle(Palette.tertiary)
                    }
                }
            }
        }
    }

    private var helperSection: some View {
        CardSection(title: L("Linux 备用工具")) {
            CardRow {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("没有图形会话的 Linux 电脑走另一套备用工具：截图、界面树、点按、移动、拖动、滚动、打字、按键，经远程屏幕的输入通道做。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("这台服务器也没开远程屏幕，备用工具同样不可用。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var neededSection: some View {
        CardSection(title: L("要让它能用，主机那边要做")) {
            CardRow {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("1. 换一台有桌面的电脑（Mac、Windows，或带 X11、Sway 会话的 Linux 桌面）。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("2. 在电脑上打开远程屏幕，并给智能体开电脑操作开关。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("3. 手机端仍调不到操作接口：操作只能由电脑上的智能体自己调，或等主机给手机开放调用。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// The 16 tools from the host's `cua_tools.json`, with the read-only flag
/// from the same file. Names are identifiers, shown as-is.
enum ComputerUseTools {
    struct Tool {
        var name: String
        var readOnly: Bool
    }

    static let all: [Tool] = [
        Tool(name: "list_apps", readOnly: true),
        Tool(name: "list_windows", readOnly: true),
        Tool(name: "get_window_state", readOnly: true),
        Tool(name: "get_desktop_state", readOnly: true),
        Tool(name: "zoom", readOnly: true),
        Tool(name: "launch_app", readOnly: false),
        Tool(name: "click", readOnly: false),
        Tool(name: "double_click", readOnly: false),
        Tool(name: "right_click", readOnly: false),
        Tool(name: "drag", readOnly: false),
        Tool(name: "scroll", readOnly: false),
        Tool(name: "type_text", readOnly: false),
        Tool(name: "press_key", readOnly: false),
        Tool(name: "hotkey", readOnly: false),
        Tool(name: "set_value", readOnly: false),
        Tool(name: "invoke_menu", readOnly: false),
    ]
}
