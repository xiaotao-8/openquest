import SwiftUI
import VisionKit

/// Pair with a computer running codync-host, one thing per page: install it,
/// then scan its code. Mirrors the original's PairingView (install → scan),
/// with Codync copy and no account (no email line, no cloud button).
/// The computer is the user's cloud host (ECS, Linux), so Linux shows first.
struct PairingView: View {
    enum Step { case install, scan }

    /// Adding another computer from the computers sheet: has a close button; closes once paired.
    var inModal = false
    /// Preview only: which step to show first (`-PreviewPairingPage`).
    var initialStep: Step = .install
    /// On the install page (onboarding only): back to the welcome.
    var onBack: (() -> Void)? = nil
    /// Finish onboarding without pairing; modal pairing simply closes when skipped.
    var onSkip: (() -> Void)? = nil
    /// Paired (also used to leave onboarding).
    var onDone: (() -> Void)? = nil
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step
    @State private var os = ComputerOS.linux

    init(inModal: Bool = false, initialStep: Step = .install, onBack: (() -> Void)? = nil, onSkip: (() -> Void)? = nil, onDone: (() -> Void)? = nil) {
        self.inModal = inModal
        self.initialStep = initialStep
        self.onBack = onBack
        self.onSkip = onSkip
        self.onDone = onDone
        self._step = State(initialValue: initialStep)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                switch step {
                case .install:
                    InstallPage(os: $os) { go(.scan) }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                case .scan:
                    ScanPage(os: os)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity)
            .clipped()
            if step == .scan {
                SkipSetupButton { if inModal { dismiss() } else { onSkip?() } }
                    .transition(.opacity)
            }
        }
        .background(Palette.background)
        .onChange(of: store.connector.pairingState) { _, newState in
            if case .paired = newState {
                dismiss()
                onDone?()
            }
        }
    }

    /// The header is only the step dots, centred; back on the scan page
    /// (or to the welcome on the install page), close only in a modal.
    private var header: some View {
        ZStack {
            HStack(spacing: 6) {
                Capsule().fill(Palette.text).frame(width: 18, height: 4)
                Capsule().fill(step == .scan ? Palette.text : Palette.accentDim).frame(width: 18, height: 4)
            }
            .accessibilityElement()
            .accessibilityLabel(step == .install ? L("第 1 步，共 2 步") : L("第 2 步，共 2 步"))
            .frame(maxWidth: .infinity)
            HStack(spacing: 6) {
                if step == .scan {
                    BackButton { go(.install) }
                } else if let onBack {
                    BackButton { onBack() }
                } else {
                    Color.clear.frame(width: 36, height: 36)
                }
                Spacer(minLength: 8)
                if inModal {
                    IconButton(L("关闭"), systemImage: "xmark") { dismiss() }
                } else {
                    Color.clear.frame(width: 36, height: 36)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(Palette.background)
    }

    private func go(_ next: Step) {
        let animation: Animation? = store.reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 1)
        withAnimation(animation) { step = next }
    }
}

private enum ComputerOS: Hashable { case mac, linux }

/// The back button for a pushed screen.
private struct BackButton: View {
    let action: () -> Void
    var body: some View {
        IconButton(L("返回"), systemImage: "chevron.left", action: action)
    }
}

/// A 36pt icon button (image + iconButton style, with an accessible label).
private struct IconButton: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    init(_ label: String, systemImage: String, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.iconButton)
        .accessibilityLabel(label)
    }
}

/// Past the setup pages without a computer, at the foot of the page.
private struct SkipSetupButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(L("跳过")).font(.headline).frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.secondary)
        .accessibilityHint(L("稍后再从管理电脑里配对。"))
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
}

private extension Text {
    /// A setup page's big title.
    func pageTitle() -> some View {
        font(.system(size: 30, weight: .semibold)).tracking(-0.5).foregroundStyle(Palette.text)
    }
}

/// Copies `text`, and says so through `copied` for a moment.
@MainActor private func copyToClipboard(_ text: String, copied: Binding<Bool>) {
    UIPasteboard.general.string = text
    withAnimation { copied.wrappedValue = true }
    Task {
        try? await Task.sleep(for: .seconds(1.5))
        withAnimation { copied.wrappedValue = false }
    }
}

// MARK: - Install

private struct InstallPage: View {
    /// The website: its first button downloads for whatever the computer runs.
    /// The host software is codync-host, so this is its download site.
    private static let websiteLink = "https://www.codync.dev"

    @Binding var os: ComputerOS
    let next: () -> Void
    @State private var linkCopied = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // A bot on the computer's screen: that's where it lives.
                    ZStack {
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 150, weight: .ultraLight))
                            .foregroundStyle(Palette.tertiary)
                        CharacterAvatar(shape: "blob", color: "blue", size: 52, mood: .working)
                            .offset(y: -12)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("在电脑上\n安装 Codync")).pageTitle()
                        Text(L("智能体在那台电脑上运行。这台 iPhone 用来和它们对话。"))
                            .font(.body)
                            .foregroundStyle(Palette.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Hint(L("在电脑上打开网站来下载 Codync"))
                        Button {
                            copyToClipboard(Self.websiteLink, copied: $linkCopied)
                        } label: {
                            Label(linkCopied ? L("已复制") : L("复制网站链接"), systemImage: linkCopied ? "checkmark" : "doc.on.doc")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .contentTransition(.opacity)
                        }
                        .buttonStyle(.secondary)
                    }

                    SegmentedChoice(options: [(.mac, "Mac"), (.linux, "Linux")], selection: $os)

                    VStack(alignment: .leading, spacing: 10) {
                        // Copied here, pasted on the computer (Universal Clipboard or a message to yourself).
                        if os == .mac {
                            Hint(L("用 Homebrew 安装"))
                            CommandBlock("brew install --cask leepokai/codync/codync")
                            Hint(L("或下载 Mac 应用"))
                            CommandBlock("https://github.com/leepokai/Codync/releases/latest/download/codync-macos.dmg")
                        } else {
                            Hint(L("运行安装程序"))
                            CommandBlock("curl -fsSL https://raw.githubusercontent.com/leepokai/Codync/main/packaging/install.sh | sh\ncodync-host install")
                            Hint(L("或用 Homebrew 安装"))
                            CommandBlock("brew install leepokai/codync/codync-host\ncodync-host install")
                        }
                        Text(os == .mac
                             ? L("打开 Codync，它会自己装好服务端。")
                             : L("装好后它一直在后台运行。"))
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondary)
                            .contentTransition(.opacity)
                    }
                    .animation(.easeInOut(duration: 0.2), value: os)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            Button(action: next) {
                Text(L("继续")).font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.primary)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }
}

/// A small label above a `CommandBlock`.
private struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.footnote).foregroundStyle(Palette.secondary).transition(.opacity)
    }
}

/// A terminal command or link with a copy button.
private struct CommandBlock: View {
    let command: String
    @State private var copied = false

    init(_ command: String) {
        self.command = command
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(command)
                .font(.footnote.monospaced())
                .foregroundStyle(Palette.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .contentTransition(.opacity)
            IconButton(copied ? L("已复制") : L("复制"), systemImage: copied ? "checkmark" : "doc.on.doc") {
                copyToClipboard(command, copied: $copied)
            }
            .contentTransition(.symbolEffect(.replace))
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(Palette.codeBackground, in: RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.2), value: command)
    }
}

// MARK: - Scan

private struct ScanPage: View {
    let os: ComputerOS
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var pairing = false
    @State private var pasted = ""
    @State private var error: String?
    /// The last error was a bare short code without a sign-in: offer the
    /// sign-in sheet next to it.
    @State private var shortCodeNeedsSignIn = false
    @State private var showingSignIn = false
    /// The phone couldn't reach the computer (not a refusal from it): the network hint helps.
    @State private var unreachable = false
    /// Bumped after a failed pair so the scanner starts looking again.
    @State private var attempt = 0
    @State private var tailscaleOn = Tailscale.isConnected

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("扫描配对码")).pageTitle()
                    Text(os == .mac
                         ? L("在 Mac 上，点菜单栏里的 Codync，再点「配对手机」。")
                         : L("在电脑上，在终端里运行："))
                        .font(.body)
                        .foregroundStyle(Palette.secondary)
                    if os == .linux { CommandBlock("codync-host pair") }
                }

                viewfinder

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        TextField(L("配对链接或配对码"), text: $pasted, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.callout.monospaced())
                            .lineLimit(1...6)
                            .onSubmit { pair(pasted) }
                        IconButton(L("配对"), systemImage: "arrow.right") { pair(pasted) }
                            .disabled(pasted.isEmpty || pairing)
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 4)
                    .padding(.vertical, 4)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))

                    // The full link is long: show all of it below the field
                    // so a paste can be checked for truncation at a glance.
                    if !pasted.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(L("已粘贴的链接"))
                                    .font(.caption)
                                    .foregroundStyle(Palette.secondary)
                                Spacer()
                                Button(L("粘贴")) { pasteFromClipboard() }
                                    .font(.caption.weight(.medium))
                                Button(L("清除"), role: .destructive) { pasted = "" }
                                    .font(.caption.weight(.medium))
                            }
                            Text(pasted)
                                .font(.caption.monospaced())
                                .foregroundStyle(Palette.text)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(L("共 %d 个字符", pasted.count))
                                .font(.caption2)
                                .foregroundStyle(Palette.tertiary)
                        }
                        .padding(12)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                }

                if let error {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(error).font(.footnote).foregroundStyle(Palette.danger)
                        if shortCodeNeedsSignIn {
                            Button(L("登录账号")) { showingSignIn = true }
                                .font(.footnote.weight(.medium))
                        }
                        // The usual cause: the phone has no road to the computer yet.
                        if unreachable {
                            Label(L("检查这台 iPhone 和电脑是否在同一 Wi-Fi，或都开了 Tailscale。"), systemImage: "wifi.exclamationmark")
                                .font(.footnote)
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    .transition(.opacity)
                }

                // How it connects is never a choice here: pairing always goes direct.
                VStack(alignment: .leading, spacing: 8) {
                    Label(L("直连：配对后这台 iPhone 直接连电脑，不经过中转。"), systemImage: "lock.fill")
                    if tailscaleOn {
                        Label(L("Tailscale 已开启：Codync 直接通过它连接。"), systemImage: "checkmark.circle.fill")
                    } else {
                        Button {
                            openURL(Tailscale.downloadURL)
                        } label: {
                            Label(L("用 Tailscale？直接连，离家也快。"), systemImage: "arrow.up.right")
                        }
                        .buttonStyle(PressScale())
                    }
                }
                .font(.footnote)
                .foregroundStyle(Palette.tertiary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .codyncSheet(isPresented: $showingSignIn) {
            SignInSheet()
        }
        // Coming back from the Tailscale app: show whether it's connected now.
        .onChange(of: scenePhase) { _, phase in if phase == .active { tailscaleOn = Tailscale.isConnected } }
    }

    /// The camera, right on the page: no extra sheet between the instruction and the scan.
    private var viewfinder: some View {
        ZStack {
            if DataScannerViewController.isSupported {
                QRScanner { code in pair(code) }
                    .id(attempt)
                // VisionKit's own hint follows the app's localizations, which stay English.
                if !pairing {
                    Text(L("查找附近的条码。"))
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 8)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .allowsHitTesting(false)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "qrcode.viewfinder").font(.system(size: 44, weight: .light))
                    Text(L("相机不可用。在下面粘贴链接。")).font(.footnote)
                }
                .foregroundStyle(Palette.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.surface)
            }
            if pairing {
                Palette.background
                VStack(spacing: 16) {
                    Spinner(size: 28)
                    // The computer asks its user first, showing the same code.
                    if case .waiting(let checkCode) = store.connector.pairingState {
                        Text(L("如果电脑问起，核对它显示的是 %@。", formattedCheckCode(checkCode)))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Palette.text)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .transition(.opacity)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: pairing)
    }

    /// "123 456" — 3 + 3 digits with a non-breaking space.
    private func formattedCheckCode(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let first = code.prefix(3)
        let second = code.suffix(3)
        return "\(first)\u{00A0}\(second)"
    }

    private func pasteFromClipboard() {
        if let string = UIPasteboard.general.string, !string.isEmpty {
            pasted = string
        }
    }

    private func pair(_ text: String) {
        // A short code works once: Return pressed again while it resolves mustn't spend it twice.
        guard !pairing else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A bare short code resolves through the account cloud. Signed out,
        // say so plainly and offer the sign-in, instead of a bare refusal.
        if let code = PairingLink.normaliseShortCode(trimmed) {
            guard store.account.isSignedIn, let cloud = store.account.cloudClient() else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    error = L("只输配对码还配不上：配对码要登录账号才能查到完整信息。请扫电脑上的二维码，或粘贴电脑显示的完整链接。")
                    shortCodeNeedsSignIn = true
                    unreachable = false
                }
                attempt += 1
                return
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                error = nil
                shortCodeNeedsSignIn = false
            }
            pairing = true
            Task {
                defer { pairing = false }
                do {
                    let linkText = try await cloud.pairingLink(code: code)
                    guard case .success(let link) = PairingLink.parse(linkText) else {
                        throw PairingProblem.invalid
                    }
                    try await runPairing(link: link)
                } catch {
                    if let cloudError = error as? CloudError, cloudError.isNotFound {
                        self.error = L("配对码过期或已用，请重新出示")
                    } else if let cloudError = error as? CloudError {
                        self.error = cloudError.localizedDescription
                    } else if error is PairingProblem {
                        self.error = L("这个链接不对。请重新复制电脑上显示的完整链接。")
                    } else if case .failed(let message) = store.connector.pairingState {
                        self.error = message
                    } else {
                        self.error = L("配对失败。请重试。")
                    }
                    unreachable = false
                    attempt += 1
                }
            }
            return
        }
        let parsed = PairingLink.parse(trimmed)
        guard case .success(let link) = parsed else {
            withAnimation(.easeInOut(duration: 0.2)) {
                if case .failure(let problem) = parsed, problem == .outdatedHost {
                    error = L("电脑版本太旧。请先更新电脑，再出示新的配对码。")
                } else {
                    error = L("这个链接不对。请重新复制电脑上显示的完整链接。")
                }
                shortCodeNeedsSignIn = false
                unreachable = false
            }
            attempt += 1
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            error = nil
            shortCodeNeedsSignIn = false
        }
        pairing = true
        Task {
            defer { pairing = false }
            do {
                try await runPairing(link: link)
            } catch {
                if case .failed(let message) = store.connector.pairingState {
                    self.error = message
                } else {
                    self.error = L("配对失败。请重试。")
                }
                if let hostError = error as? HostCallError {
                    switch hostError {
                    case .unreachable, .timeout: unreachable = true
                    default: break
                    }
                }
                attempt += 1
            }
        }
    }

    /// Runs the pairing flow for a validated link: the computer approves
    /// with the 6-digit check code, then normal mode connects. Throws the
    /// host's message on failure.
    private func runPairing(link: PairingLink) async throws {
        let deviceName = UIDevice.current.name
        _ = try await store.connector.pair(link: link, deviceName: deviceName)
        await MainActor.run { store.writeWidgetSnapshot() }
        pasted = ""
    }
}

/// VisionKit live QR scanner.
private struct QRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .fast,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case let .barcode(code) in items {
                if let value = code.payloadStringValue, value.hasPrefix("codync://"), !done {
                    done = true
                    scanner.stopScanning()
                    onCode(value)
                }
            }
        }
    }
}
