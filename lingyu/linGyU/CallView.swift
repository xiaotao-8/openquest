import SwiftUI

/// A voice call with a bot: a floating capsule bar over the transcript,
/// as the original does it — the bot's avatar pulses while it speaks,
/// dotted level line in the middle, settings gear, mic mute, red hang-up.
/// What the user says is transcribed live below; the bot's replies are
/// read aloud. The call ends as one titled line in the chat
/// ("通话 · 00:16") that opens its transcript.
struct CallView: View {
    var bot: Bot
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Called once, when the call ends, with the call's lines and length
    /// in seconds — the chat writes them as one call line.
    var onEnd: ([CallLine], Int) -> Void

    @StateObject private var voice: VoiceStore
    @State private var showingSettings = false
    @State private var didEnd = false

    init(bot: Bot, store: AppStore, onEnd: @escaping ([CallLine], Int) -> Void) {
        self.bot = bot
        self.onEnd = onEnd
        _voice = StateObject(wrappedValue: VoiceStore(store: store, botId: bot.id, botName: bot.name))
    }

    var body: some View {
        VStack(spacing: 0) {
            bar
                .padding(.horizontal, 12)
                .padding(.top, 12)
            if case .failed(let message) = voice.phase {
                statusLine(message, color: Palette.danger)
            } else if voice.phase == .connecting {
                statusLine(L("正在接通…"), color: Palette.secondary)
            } else if voice.phase == .live, voice.isSpeaking {
                statusLine(L("正在说话"), color: Palette.secondary)
            }
            transcript
            Spacer()
            privacyNote
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
        .background(Palette.background)
        .onAppear {
            Task { await voice.start() }
        }
        .onDisappear {
            endOnce()
        }
        .codyncSheet(isPresented: $showingSettings) {
            NavigationStack { VoiceSettingsView() }
        }
    }

    // MARK: - Top capsule bar

    private var bar: some View {
        HStack(spacing: 10) {
            avatar
            LevelDots(level: voice.level, speaking: voice.isSpeaking,
                      connecting: voice.phase == .connecting, reduceMotion: reduceMotion)
                .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20)
                .accessibilityLabel(statusText)
            round(L("通话设置"), "gearshape") { showingSettings = true }
            let muted = voice.muted
            round(muted ? L("取消静音") : L("静音"), muted ? "mic.slash" : "mic", on: muted) {
                voice.muted.toggle()
            }
            Button {
                endOnce()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Palette.danger, in: Circle())
            }
            .buttonStyle(PressScale())
            .accessibilityLabel(L("挂断"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .glass(in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
    }

    /// The bot; tapping it while it talks cuts the reply short.
    private var avatar: some View {
        Button {
            voice.interrupt()
        } label: {
            BotAvatar(bot: bot, members: [], size: 34)
                .scaleEffect(voice.isSpeaking && !reduceMotion ? 1.1 : 1)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                           value: voice.isSpeaking)
        }
        .buttonStyle(.plain)
        .disabled(!voice.isSpeaking)
        .accessibilityLabel(voice.isSpeaking ? L("打断") : bot.name)
    }

    private func round(_ label: String, _ symbol: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(on ? Palette.onAccent : Palette.text)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 46, height: 46)
                .background(on ? Palette.accentFill : Palette.background, in: Circle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(label)
    }

    private func statusLine(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glass(in: Capsule())
            .padding(.top, 8)
            .transition(.opacity)
    }

    private var statusText: String {
        switch voice.phase {
        case .connecting: return L("正在接通")
        case .failed: return L("无法接通")
        case .live: return voice.isSpeaking ? L("正在说话") : L("正在听")
        case .idle, .ended: return L("通话已结束")
        }
    }

    // MARK: - Live transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(voice.lines) { line in
                        TranscriptLine(line: line, botName: bot.name)
                            .id(line.id)
                    }
                    if !voice.heard.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Text(L("你"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.secondary)
                            Text(voice.heard)
                                .font(.body)
                                .foregroundStyle(Palette.tertiary)
                        }
                        .id("heard")
                    }
                    Color.clear.frame(height: 4).id("bottom")
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .onChange(of: voice.lines.count) { _, _ in
                withAnimation(.easeOut(duration: 0.24)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: voice.heard) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Privacy note

    /// Muse's call privacy, in its own meaning: the bot can hear the
    /// user, but it cannot see the user.
    private var privacyNote: some View {
        Text(L("通话中智能体能听到你说话，但看不到你。"))
            .font(.footnote)
            .foregroundStyle(Palette.secondary)
            .multilineTextAlignment(.center)
    }

    private func endOnce() {
        guard !didEnd else { return }
        didEnd = true
        let lines = voice.lines
        let seconds = voice.elapsedSeconds
        voice.end()
        onEnd(lines, seconds)
    }
}

private struct TranscriptLine: View {
    var line: CallLine
    var botName: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(line.speaker == .user ? L("你") : botName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(line.speaker == .user ? Palette.secondary : Palette.text)
                .lineLimit(1)
            Text(line.text)
                .font(.body)
                .foregroundStyle(Palette.text)
                .textSelection(.enabled)
        }
    }
}

/// The dotted level line in the call bar: bars rise with the microphone
/// level while listening, and pulse while the bot speaks.
private struct LevelDots: View {
    var level: Float
    var speaking: Bool
    var connecting: Bool
    var reduceMotion: Bool

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Palette.secondary)
                    .frame(width: 3, height: height(for: index))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: level)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: speaking)
    }

    private func height(for index: Int) -> CGFloat {
        if connecting { return 4 }
        // While the bot speaks the microphone is off, so the bars hold a
        // fixed wave instead of falling flat; while listening they follow
        // the microphone level.
        if speaking { return 6 + CGFloat(3 - abs(index - 3)) * 3 }
        let wave = 1 - abs(Float(index) - 3) / 3
        return 4 + CGFloat(level * wave) * 16
    }
}
