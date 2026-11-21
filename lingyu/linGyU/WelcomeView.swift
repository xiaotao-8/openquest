import Security
import SwiftUI

/// First-launch flow: Welcome → Install → Scan → Tabs (or Skip → Tabs).
/// Steps slide + fade (spring 0.45s, fade only with Reduce Motion).
struct WelcomeView: View {
    var onSkip: () -> Void
    @EnvironmentObject private var store: AppStore
    @State private var step = 0
    @State private var phase: Double = 0
    @State private var glimpseDone = false
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            switch step {
            case 0:
                welcomeStep
            case 1:
                installStep
            default:
                PairingView(onDone: {
                    store.showingWelcome = false
                })
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 1), value: step)
        .onAppear {
            startBobbing()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                glimpseDone = true
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            crew
                .frame(height: 170)
                .padding(.top, 24)
            ChatGlimpse(done: glimpseDone)
                .padding(.horizontal, 20)
                .padding(.top, 8)
            Text(L("你的智能体团队\n在电脑上替你干活"))
                .font(.system(size: 34, weight: .semibold))
                .tracking(-0.6)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.text)
                .padding(.top, 24)
                .padding(.horizontal, 24)
            Text(L("给每个智能体起个名字、指一个项目，它们在你的电脑上替你干活。"))
                .font(.body)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 32)
            Spacer()
            PrimaryActionButton(title: L("开始配对")) {
                step = 1
            }
            .padding(.horizontal, 20)
            Button(L("跳过，先看看")) {
                onSkip()
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Palette.secondary)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }

    /// Five bobbing avatars, positions and colours from the original.
    private var crew: some View {
        ZStack {
            ForEach(Array(crewMembers.enumerated()), id: \.offset) { index, member in
                AvatarView(name: member.letter, color: member.color, shape: member.shape, size: member.size)
                    .offset(x: member.offset.x, y: member.offset.y + bobOffset(index: index))
                    .opacity(member.opacity)
            }
        }
    }

    private struct CrewMember {
        var letter: String
        var color: String
        var shape: String
        var size: CGFloat
        var offset: CGPoint
        var opacity: Double = 1
    }

    private var crewMembers: [CrewMember] {
        [
            CrewMember(letter: "L", color: "blue", shape: "blob", size: 92, offset: CGPoint(x: 0, y: 0)),
            CrewMember(letter: "J", color: "orange", shape: "squircle", size: 64, offset: CGPoint(x: -104, y: -34)),
            CrewMember(letter: "Y", color: "violet", shape: "teardrop", size: 58, offset: CGPoint(x: 100, y: -46)),
            CrewMember(letter: "G", color: "green", shape: "hex", size: 48, offset: CGPoint(x: -76, y: 64)),
            CrewMember(letter: "U", color: "magenta", shape: "cloud", size: 52, offset: CGPoint(x: 84, y: 58)),
        ]
    }

    private func bobOffset(index: Int) -> CGFloat {
        if store.reduceMotion { return 0 }
        return 5 * CGFloat(sin(phase * 1.3 + Double(index) * 1.7))
    }

    private func startBobbing() {
        if store.reduceMotion { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            phase += 0.05
        }
    }

    // MARK: - Install (pairing step 1)

    @State private var serverAddress = "47.238.160.204"
    @State private var serverToken = ""
    @State private var copied = false

    private var installStep: some View {
        VStack(spacing: 0) {
            stepProgress(current: 0)
                .padding(.top, 12)
            ZStack {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 150, weight: .ultraLight))
                    .foregroundStyle(Palette.tertiary)
                AvatarView(name: "L", color: "blue", shape: "blob", size: 52)
                    .offset(y: -12)
            }
            .padding(.top, 8)
            Text(L("在你的电脑上安装服务端"))
                .font(.system(size: 30, weight: .semibold))
                .tracking(-0.5)
                .foregroundStyle(Palette.text)
                .padding(.top, 24)
            Text(L("智能体在电脑上运行，这部手机是和它们说话的窗口。"))
                .font(.body)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 32)
            VStack(spacing: 12) {
                TextField(L("服务器地址"), text: $serverAddress)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                SecureField(L("令牌"), text: $serverToken)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            Spacer()
            Button {
                UIPasteboard.general.string = installLink
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    copied = false
                }
            } label: {
                HStack {
                    Text(copied ? L("已复制") : L("复制安装链接"))
                    if copied {
                        Image(systemName: "checkmark")
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
            }
            .buttonStyle(.secondary)
            .padding(.horizontal, 20)
            PrimaryActionButton(title: L("继续")) {
                saveServerConfig()
                step = 2
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .navigationBarBackButtonHidden(true)
    }

    private var installLink: String {
        "https://\(serverAddress)/install"
    }

    private func saveServerConfig() {
        UserDefaults.standard.set(serverAddress, forKey: "cn.lingyu.serverAddress")
        if !serverToken.isEmpty {
            ServerTokenStore.save(serverToken)
        }
    }

    private func stepProgress(current: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Palette.text : Palette.accentDim)
                    .frame(width: 18, height: 4)
            }
        }
        .accessibilityLabel(L("第 %d 步，共 2 步", current + 1))
    }
}

/// The demo conversation on the Welcome page: one question → working → done.
/// Copy rewritten in Chinese; the original's English lines are not reused.
struct ChatGlimpse: View {
    var done: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                Text(L("修好那个不稳定的登录测试"))
                    .font(.subheadline)
                    .foregroundStyle(Palette.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Palette.bubbleUser, in: RoundedRectangle(cornerRadius: 18))
            }
            HStack(alignment: .top, spacing: 8) {
                AvatarView(name: "L", color: "blue", shape: "blob", size: 28)
                if done {
                    Text(L("搞定了，登录测试已修复，跑了三遍都通过。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Palette.bubbleAgent, in: RoundedRectangle(cornerRadius: 18))
                } else {
                    Text(L("工作中…"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.tertiary)
                        .padding(.vertical, 4)
                }
                Spacer()
            }
        }
    }
}

/// The server token lives in the Keychain, never in UserDefaults or files.
enum ServerTokenStore {
    private static let service = "cn.lingyu.server-token"
    private static let account = "local"

    static func save(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecAttrSynchronizable as String] = false
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load() -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
