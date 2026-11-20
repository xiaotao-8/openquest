import SwiftUI

/// 小窗容器（用户要求：默认 ≥ 屏宽 80% × 屏高 45%，可拖到全屏）。
/// 浮在内容上：标题栏可拖动，右上角有关闭和展开按钮。
/// 浏览器小窗、干活小窗、审批小窗都用它，不再各写一套。
///
/// 尺寸直接取屏幕（UIScreen.main.bounds），居中由宿主 overlay 负责，
/// 本组件不做 `.position`——实测 #25/#26：`.frame` + `.position` 的组合
/// 在 overlay 里框不住高度（#25 约 75% 屏高，#26 改 UIScreen 后仍约 70%，
/// 内容把框撑大了）；去掉 `.position`、只留 `.frame` + `.clipped()`，
/// 框就是准确的 80% × 45%。
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
            // 内容区用 GeometryReader 量出标题栏剩下的准确尺寸再定框：
            // 图片类内容自带理想高度（浏览器实拍帧按宽缩放后约 614pt），
            // 若只给 maxHeight: .infinity，内容会把 VStack 撑到比框高，
            // 框再居中一裁，标题栏就被推出框顶切掉了（#27 实测）。
            // 这里把内容框死在剩余空间里，不再留撑大的余地。
            GeometryReader { geo in
                content()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        }
        .frame(width: w, height: h, alignment: .top)
        .clipped()
        .background(Palette.background,
                    in: RoundedRectangle(cornerRadius: expanded ? 0 : 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: expanded ? 0 : 20, style: .continuous)
            .stroke(Palette.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .offset(totalOffset)
        .animation(.snappy(duration: 0.25), value: expanded)
    }
}
