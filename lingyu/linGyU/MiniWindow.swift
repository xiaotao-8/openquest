import SwiftUI

/// The browser mini window (§4.8, §1.2): floats over the chat while the AI
/// calls the server browser, default ≥80% × 45%, expandable to fullscreen.
/// Sizing comes from `UIScreen.main.bounds` — never from the host's
/// GeometryReader — and the window is centered via the parent's
/// `.overlay(alignment: .center)`, with an explicit frame + `.clipped()`
/// (AGENTS.md MiniWindow rules). Phase 1 is the shell: the host has no
/// server-browser API yet, so the content area shows the waiting state;
/// the live page (S18) is deferred to the phase that adds the host API.
struct MiniWindow: View {
    var title: String
    var onClose: () -> Void
    @State private var isFullscreen = false

    var body: some View {
        let screen = UIScreen.main.bounds
        let width = isFullscreen ? screen.width : max(screen.width * 0.8, 300)
        let height = isFullscreen ? screen.height : screen.height * 0.45
        VStack(spacing: 0) {
            titleBar
            GeometryReader { geometry in
                content
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .background(Palette.background, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 4)
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 14))
                .foregroundStyle(Palette.secondary)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
            Spacer()
            Button {
                isFullscreen.toggle()
            } label: {
                Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFullscreen ? L("退出全屏") : L("全屏"))
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("关闭"))
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Palette.surface)
    }

    private var content: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(Palette.tertiary)
            Text(L("服务器浏览器即将可用"))
                .font(.headline)
                .foregroundStyle(Palette.text)
            Text(L("智能体调用服务器浏览器时，这里会实时显示浏览器画面。"))
                .font(.body)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}
