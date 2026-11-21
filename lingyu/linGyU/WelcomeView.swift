import SwiftUI

/// First-launch flow: Welcome → Pairing (install → scan) → Tabs (or Skip → Tabs).
/// Steps slide + fade (spring 0.45s, fade only with Reduce Motion).
struct WelcomeView: View {
    var onSkip: () -> Void
    @EnvironmentObject private var store: AppStore
    @State private var pairing = false
    @State private var phase: Double = 0
    @State private var glimpseDone = false
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            if pairing {
                PairingView(onBack: { pairing = false }, onSkip: onSkip, onDone: {
                    store.showingWelcome = false
                })
            } else {
                welcomeStep
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 1), value: pairing)
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
            GeometryReader { _ in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 24)
                        crew
                            .frame(height: 170)
                        ChatGlimpse(done: glimpseDone)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("你的智能体团队\n在电脑上替你干活"))
                                .font(.system(size: 34, weight: .semibold))
                                .tracking(-0.6)
                                .foregroundStyle(Palette.text)
                            Text(L("给每个智能体起个名字、指一个项目，它们在你的电脑上替你干活。"))
                                .font(.body)
                                .foregroundStyle(Palette.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        Spacer(minLength: 24)
                    }
                }
            }
            VStack(spacing: 10) {
                PrimaryActionButton(title: L("开始配对")) {
                    pairing = true
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)
        }
    }

    /// Five bobbing avatars, positions and colours from the original.
    private var crew: some View {
        ZStack {
            ForEach(Array(crewMembers.enumerated()), id: \.offset) { index, member in
                CharacterAvatar(shape: member.shape, color: member.color, size: member.size, mood: member.mood)
                    .offset(x: member.offset.x, y: member.offset.y + bobOffset(index: index))
                    .opacity(member.opacity)
            }
        }
    }

    private struct CrewMember {
        var color: String
        var shape: String
        var size: CGFloat
        var mood: CharacterAvatar.Mood
        var offset: CGPoint
        var opacity: Double = 1
    }

    private var crewMembers: [CrewMember] {
        [
            CrewMember(color: "blue", shape: "blob", size: 92, mood: .working, offset: CGPoint(x: 0, y: 0)),
            CrewMember(color: "orange", shape: "squircle", size: 64, mood: .idle, offset: CGPoint(x: -104, y: -34)),
            CrewMember(color: "violet", shape: "teardrop", size: 58, mood: .working, offset: CGPoint(x: 100, y: -46)),
            CrewMember(color: "green", shape: "hex", size: 48, mood: .idle, offset: CGPoint(x: -76, y: 64)),
            CrewMember(color: "magenta", shape: "cloud", size: 52, mood: .needsInput, offset: CGPoint(x: 84, y: 58)),
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

}

/// The demo conversation on the Welcome page: one question → working → done.
/// Copy rewritten in Chinese; the original's English lines are not reused.
struct ChatGlimpse: View {
    var done: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                Text(L("修好那个不稳定的登录测试"))
                    .font(.subheadline)
                    .foregroundStyle(Palette.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Palette.bubbleUser, in: RoundedRectangle(cornerRadius: 18))
            }
            HStack(alignment: .bottom, spacing: 8) {
                CharacterAvatar(shape: "blob", color: "blue", size: 28, mood: done ? .idle : .working)
                if done {
                    Text(L("搞定了，登录测试已修复，跑了三遍都通过。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Palette.bubbleAgent, in: RoundedRectangle(cornerRadius: 18))
                } else {
                    Text(L("工作中…"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.tertiary)
                }
                Spacer()
            }
        }
    }
}
