import AVFoundation
import SwiftUI

/// Settings → Voice service: which engine carries calls and dictation,
/// which on-device Chinese voice reads replies, and whether replies are
/// read aloud. Only the on-device engine works: the computer's credential
/// store is locked (voiceStatus, probed 2026-11-22, still errors), so no
/// voice key can be saved on the computer and the realtime / Live engines
/// and the Speech-mode providers stay disabled with the reason shown —
/// they never pretend to work.
struct VoiceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(VoicePrefs.engine) private var engine = "device"
    @AppStorage(VoicePrefs.voiceIdentifier) private var voiceIdentifier = ""
    @AppStorage(VoicePrefs.rate) private var rate = Double(AVSpeechUtteranceDefaultSpeechRate)
    @AppStorage(VoicePrefs.pause) private var pause = 1.5
    @AppStorage(VoicePrefs.autoReadAloud) private var autoReadAloud = true
    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var disabledReason: String?

    /// The host's own words for the locked vault (a diagnostic, shown
    /// verbatim in the "why unavailable" dialog, not localised copy).
    private static let hostVoiceError =
        "Secure credential storage is locked or unavailable. Unlock Keychain on macOS, " +
        "or start and unlock a Secret Service keyring in this Linux user's D-Bus session."

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("语音服务")) {
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    engineSection
                    speechModeSection
                    voiceSection
                    readAloudSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(Palette.background)
        .onAppear {
            voices = VoiceStore.chineseVoices()
        }
        .codyncDialog(
            isPresented: Binding(
                get: { disabledReason != nil },
                set: { if !$0 { disabledReason = nil } }
            ),
            title: L("为什么不可用"),
            message: disabledReason ?? "",
            actions: [CodyncDialogAction(title: L("好"), action: {})]
        )
    }

    // MARK: - Engine

    private var engineSection: some View {
        CardSection(title: L("语音引擎"), footer: L("识别与朗读都在这台设备上完成。实时语音与 Live 须把语音 Key 存在电脑端，电脑端凭证库未解锁，暂时不可用。")) {
            CardRow {
                ValueRow(label: L("通话引擎")) {
                    ChoicePicker(selection: $engine, options: engineOptions, disabled: ["openai", "gemini"])
                }
            }
            Hairline()
            CardRow {
                Button {
                    disabledReason = L("电脑端凭证库未解锁，无法保存语音 Key。") + "\n\n" + Self.hostVoiceError
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock")
                            .font(.caption)
                            .foregroundStyle(Palette.secondary)
                        Text(L("电脑端语音服务不可用"))
                            .foregroundStyle(Palette.secondary)
                        Spacer()
                        Text(L("查看原因"))
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Engine names are product identifiers, not localisable copy: the
    /// on-device label goes through L, the provider names stay literal.
    private var engineOptions: [(id: String, label: String)] {
        [
            ("device", L("设备语音")),
            ("openai", "OpenAI Realtime · gpt-realtime-2.1"),
            ("gemini", "Gemini Live · gemini-3.8-live"),
        ]
    }

    // MARK: - Speech mode (host-key providers)

    private var speechModeSection: some View {
        CardSection(title: L("语音模式"), footer: L("这两个模式用电脑端的语音服务识别与朗读，须先把 Key 存在电脑端。")) {
            CardRow {
                disabledProviderRow(name: "DeepSeek")
            }
            Hairline()
            CardRow {
                disabledProviderRow(name: "Volcengine")
            }
        }
    }

    private func disabledProviderRow(name: String) -> some View {
        Button {
            disabledReason = L("电脑端凭证库未解锁，无法保存语音 Key。") + "\n\n" + Self.hostVoiceError
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "lock")
                    .font(.caption)
                    .foregroundStyle(Palette.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("%@ 语音", name))
                        .foregroundStyle(Palette.secondary)
                    Text(L("走电脑端 Key，不可用"))
                        .font(.caption)
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
                Text(L("查看原因"))
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Voice

    private var voiceSection: some View {
        CardSection(title: L("声音"), footer: L("朗读通话回复用的声音，取自这台设备上已安装的中文语音。")) {
            CardRow {
                if voices.isEmpty {
                    Text(L("这台设备上没有可用的中文语音。"))
                        .foregroundStyle(Palette.secondary)
                } else {
                    ValueRow(label: L("朗读声音")) {
                        ChoicePicker(selection: $voiceIdentifier, options: voices.map {
                            ($0.identifier, "\($0.name) · \($0.language)")
                        })
                    }
                }
            }
            Hairline()
            CardRow {
                ValueRow(label: L("朗读速度")) {
                    ChoicePicker(selection: $rate, options: [
                        (0.42, L("慢")),
                        (Double(AVSpeechUtteranceDefaultSpeechRate), L("正常")),
                        (0.56, L("快")),
                    ])
                }
            }
            Hairline()
            CardRow {
                ValueRow(label: L("停顿多久后发送"), detail: L("通话里停顿这么久，就把你刚说的话发给智能体。")) {
                    ChoicePicker(selection: $pause, options: [
                        (1.0, L("1 秒")),
                        (1.5, L("1.5 秒")),
                        (2.5, L("2.5 秒")),
                    ])
                }
            }
        }
    }

    // MARK: - Read aloud

    private var readAloudSection: some View {
        CardSection(title: L("朗读"), footer: L("关掉后，通话里智能体的回复只显示文字，不自动读出来。")) {
            CardRow {
                SwitchRow(label: L("自动朗读回复"), detail: L("通话中智能体的回复自动读出来。"), isOn: $autoReadAloud)
            }
        }
    }
}
