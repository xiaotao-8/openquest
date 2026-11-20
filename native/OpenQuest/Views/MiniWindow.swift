import SwiftUI

/// 小窗容器（用户要求：默认 ≥ 屏宽 80% × 屏高 45%，可拖到全屏）。
/// 浮在内容上：标题栏可拖动，右上角有关闭和展开按钮。
/// 浏览器小窗、干活小窗、审批小窗都用它，不再各写一套。
///
/// 尺寸直接取屏幕（UIScreen.main.bounds），不用 overlay 里 GeometryReader
/// 量的宿主尺寸——实测 #25：宿主量出来的高比屏幕大，小窗被撑到约 75% 屏高，
/// 盖住了对话；按屏幕算才是准确的 80% × 45% 居中。
struct MiniWindow<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var baseOffset = CGSize.zero
    @State private var dragOffset = CGSize.zero
    @State private var expanded = false

    private var screen: CGSize { UIScreen.main.bounds.size }

    private var totalOffset: CGSize {
        expanded ? .zero : CGSize(width: baseOffset.width + dragOffset.width,
                                  height: baseOffset.height + dragOffset.height)
    }

    var body: some View {
        let w = expanded ? screen.width : max(screen.width * 0.8, 280)
        let h = expanded ? screen.height : max(screen.height * 0.45, 240)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                StatusDot(kind: .running)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                    Image(systemName: expanded
                          ? "arrow.down.right.and.arrow.up.left"
                          : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.secondary)
                        .frame(width: 32, height: 32)
                        .background(Palette.control, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "收起小窗" : "全屏")
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Palette.control, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭小窗")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Palette.grouped)
            .gesture(
                DragGesture()
                    .onChanged { v in
                        guard !expanded else { return }
                        dragOffset = v.translation
                    }
                    .onEnded { v in
                        guard !expanded else { return }
                        // 拖完别让小窗跑出屏幕：至少留一半在屏内。
                        let nx = baseOffset.width + v.translation.width
                        let ny = baseOffset.height + v.translation.height
                        baseOffset = CGSize(
                            width: min(max(nx, -screen.width * 0.3),
                                       screen.width * 0.3),
                            height: min(max(ny, -screen.height * 0.3),
                                        screen.height * 0.3))
                        dragOffset = .zero
                    }
            )
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: w, height: h)
        .background(Palette.background,
                    in: RoundedRectangle(cornerRadius: expanded ? 0 : 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: expanded ? 0 : 20, style: .continuous)
            .stroke(Palette.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .position(x: screen.width / 2, y: screen.height / 2)
        .offset(totalOffset)
        .animation(.snappy(duration: 0.25), value: expanded)
    }
}
