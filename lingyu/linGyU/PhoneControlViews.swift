import SwiftUI

/// 操控手机 (iCTRL): lets a bot operate other apps on this phone, via the
/// third-party iCTRL app and its on-device service.
///
/// Status machine: checking → running / not installed / not running.
/// The check polls `http://127.0.0.1:8200/whoami` every 5 seconds while
/// this page is open. On the simulator 127.0.0.1 is the simulator itself,
/// so the service never answers there and the page honestly shows
/// "not installed". On a real phone, "not installed" vs "not running" is
/// told apart by whether the `ictrl://` scheme opens: that only works once
/// the scheme is declared in the app's Info.plist (a coordinator follow-up;
/// until then a stopped iCTRL also reads as "not installed", and the
/// footnote says so).
///
/// Nothing here claims the feature is verified: whether iCTRL installs and
/// runs under a free personal signature on the user's iPhone SE 2 can only
/// be settled by the real-device test gate in the phase notes. Start / stop
/// go through the `ictrl://start` / `ictrl://stop` deep links. The
/// recording toggle is local-only (UserDefaults); recordings stay on this
/// phone, have no audio, and play back at speed.
struct PhoneControlView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var status: PhoneControlStatus = .checking
    @State private var lastChecked: Date?
    @State private var openFailed = false
    @AppStorage("cn.lingyu.phoneRecorder.enabled") private var recordEnabled = false

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("操控手机")) {
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusSection
                    controlsSection
                    recordingSection
                    tutorialSection
                    notesSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(Palette.background)
        .task {
            while !Task.isCancelled {
                await checkStatus()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private var statusSection: some View {
        CardSection(title: L("状态")) {
            CardRow {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle().fill(status.dotColor).frame(width: 10, height: 10)
                        Text(status.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.text)
                    }
                    Text(status.detail)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let lastChecked {
                        Text(L("上次检查：%@", Self.timeFormatter.string(from: lastChecked)))
                            .font(.caption)
                            .foregroundStyle(Palette.tertiary)
                    }
                }
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var controlsSection: some View {
        CardSection(title: L("服务")) {
            CardRow {
                Button(L("启动")) {
                    openDeepLink("ictrl://start")
                }
                .font(.body)
                .foregroundStyle(Palette.text)
            }
            Hairline()
            CardRow {
                Button(L("停止")) {
                    openDeepLink("ictrl://stop")
                }
                .font(.body)
                .foregroundStyle(Palette.text)
            }
            if openFailed {
                Hairline()
                CardRow {
                    Text(L("打不开：可能还没装 iCTRL，先按下面的教程装好。"))
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var recordingSection: some View {
        CardSection(title: L("录像")) {
            CardRow {
                SwitchRow(
                    label: L("录下操作过程"),
                    detail: L("录像只留在本机，没有声音，可以倍速回看。"),
                    isOn: $recordEnabled
                )
            }
        }
    }

    private var tutorialSection: some View {
        CardSection(title: L("安装")) {
            CardRow {
                Link(destination: URL(string: "https://github.com/OpenMinis/iCTRL")!) {
                    HStack {
                        Text(L("安装教程"))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.tertiary)
                    }
                }
            }
            Hairline()
            CardRow {
                Text(L("要 iOS 17.4 以上、打开开发者模式并侧载安装；免费个人签名就可以，第一次设置要一次电脑。"))
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var notesSection: some View {
        CardSection(title: L("使用须知")) {
            CardRow {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("能用本机能力办的事，不去点界面；先读屏幕再动手，每点一下核对画面是否变了。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("只在这台手机上：服务只在本机监听，远程访问保持关闭。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("智能体看到的其他 App 画面，会随对话发给模型服务商。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("付款、删除、替你发消息之前一定先问你；密码、验证码、人机验证留给你自己。操作时屏幕顶部有运行提示，同时按住两个音量键即停。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func openDeepLink(_ string: String) {
        guard let url = URL(string: string) else { return }
        UIApplication.shared.open(url) { done in
            if !done {
                openFailed = true
            }
        }
    }

    private func checkStatus() async {
        guard let url = URL(string: "http://127.0.0.1:8200/whoami") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                status = .running
            } else {
                status = .notRunning
            }
        } catch {
            if UIApplication.shared.canOpenURL(URL(string: "ictrl://")!) {
                status = .notRunning
            } else {
                status = .notInstalled
            }
        }
        lastChecked = Date()
    }
}

enum PhoneControlStatus {
    case checking
    case notInstalled
    case notRunning
    case running

    var title: String {
        switch self {
        case .checking: return L("正在检查…")
        case .notInstalled: return L("未安装")
        case .notRunning: return L("未运行")
        case .running: return L("运行中")
        }
    }

    var detail: String {
        switch self {
        case .checking:
            return L("正在问本机的操控服务是否在运行。")
        case .notInstalled:
            return L("本机没有应答：可能还没装 iCTRL，也可能装了但没在运行。模拟器上一定显示这一项，因为模拟器里没有 iCTRL。")
        case .notRunning:
            return L("已装 iCTRL，但服务没在运行。点启动，或在 iCTRL 里打开服务。")
        case .running:
            return L("操控服务正在运行，智能体可以操作这台手机上的其他 App。")
        }
    }

    var dotColor: Color {
        switch self {
        case .checking: return Palette.tertiary
        case .notInstalled: return Palette.tertiary
        case .notRunning: return Palette.warning
        case .running: return Palette.added
        }
    }
}
