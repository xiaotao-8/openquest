import SwiftUI

/// Pairing step 2: paste the full pairing link from the computer. A bare
/// short code cannot be resolved by the app alone (no cloud client in
/// Phase 1), so it shows guidance to fetch the full link instead (§8.6,
/// option a). While waiting for approval the 6-digit check code is shown.
struct PairingView: View {
    var onDone: (() -> Void)? = nil
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var linkText = ""
    @State private var shortCodeText = ""
    @State private var errorMessage: String?
    @State private var isPairing = false

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("配对电脑")) {
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    stepProgress
                    Text(L("在电脑上运行配对命令，把显示的完整链接粘贴到这里。"))
                        .font(.body)
                        .foregroundStyle(Palette.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("配对链接"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.text)
                        TextField(L("粘贴配对链接"), text: $linkText)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("配对码"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.text)
                        TextField(L("如 QRTX-4821"), text: $shortCodeText)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.allCharacters)
                            .disableAutocorrection(true)
                            .onChange(of: shortCodeText) { _, newValue in
                                if let normalised = PairingLink.normaliseShortCode(newValue) {
                                    shortCodeText = normalised
                                }
                            }
                        if !shortCodeText.isEmpty {
                            Text(L("只凭配对码连不上。请在电脑上出示完整链接，粘贴到上面。"))
                                .font(.caption)
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.body)
                            .foregroundStyle(Palette.danger)
                    }
                    if case .waiting(let checkCode) = store.connector.pairingState {
                        waitingCard(checkCode: checkCode)
                    }
                    Spacer(minLength: 20)
                    PrimaryActionButton(title: isPairing ? L("正在配对…") : L("配对"), isEnabled: !isPairing && !linkText.isEmpty) {
                        startPairing()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .background(Palette.background)
        .onChange(of: store.connector.pairingState) { _, newState in
            if case .paired = newState {
                isPairing = false
                dismiss()
                onDone?()
            }
        }
    }

    private var stepProgress: some View {
        HStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { index in
                Capsule()
                    .fill(index == 1 ? Palette.text : Palette.accentDim)
                    .frame(width: 18, height: 4)
            }
        }
        .accessibilityLabel(L("第 2 步，共 2 步"))
    }

    private func waitingCard(checkCode: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Spinner(size: 16)
                Text(L("在电脑上批准这次配对"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.text)
            }
            Text(L("核对码 %@（电脑上显示的须一致）", formattedCheckCode(checkCode)))
                .font(.footnote)
                .foregroundStyle(Palette.secondary)
        }
        .padding(16)
        .background(Palette.bubbleAgent, in: RoundedRectangle(cornerRadius: 16))
    }

    /// "123 456" — 3 + 3 digits with a non-breaking space.
    private func formattedCheckCode(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let first = code.prefix(3)
        let second = code.suffix(3)
        return "\(first)\u{00A0}\(second)"
    }

    private func startPairing() {
        let parsed = PairingLink.parse(linkText)
        guard case .success(let link) = parsed else {
            if case .failure(let problem) = parsed, problem == .outdatedHost {
                errorMessage = L("电脑版本太旧。请先更新电脑，再出示新的配对码。")
            } else {
                errorMessage = L("这个链接不对。请重新复制电脑上显示的完整链接。")
            }
            return
        }
        errorMessage = nil
        isPairing = true
        let deviceName = UIDevice.current.name
        Task {
            do {
                _ = try await store.connector.pair(link: link, deviceName: deviceName)
            } catch {
                isPairing = false
                if case .failed(let message) = store.connector.pairingState {
                    errorMessage = message
                } else {
                    errorMessage = L("配对失败。请重试。")
                }
            }
        }
    }
}
