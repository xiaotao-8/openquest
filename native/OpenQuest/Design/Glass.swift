import SwiftUI

/// 浅底上的玻璃与共用小件（FishPocket 的 Theme.swift 同款做法）：
/// iOS 26 真液态玻璃 + 细描边；深底上沿用旧的 liquidGlass（GlassStyle.swift）。
extension View {
    /// 浅底玻璃面：真玻璃 + 描边。
    func glassSurface<S: Shape>(_ shape: S) -> some View {
        self
            .glassEffect(.regular, in: shape)
            .overlay(shape.stroke(Palette.stroke, lineWidth: 1))
    }

    /// 输入框表面：r28 玻璃（FishPocket composerSurface）。
    func composerSurface() -> some View {
        glassSurface(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    /// 顶部标题胶囊（FishPocket barTitleGlass）。
    func barTitleGlass() -> some View {
        glassSurface(Capsule())
    }

    /// 悬浮栏玻璃（FishPocket floatingGlass）。
    func floatingGlass() -> some View {
        glassSurface(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    /// 44pt 最小点击区。
    func hitTarget() -> some View {
        self.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }

    /// 贴合内容的 bottom sheet（FishPocket FittedSheet）：按内容定高，大圆角，无指示条。
    func fittedSheet() -> some View {
        modifier(FittedSheetModifier())
    }

    /// 主按钮：黑底白字大胶囊（提问卡 Commit、审批 Allow 同款）。
    func primaryCapsule() -> some View {
        self
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Palette.onInk)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Palette.ink, in: Capsule())
    }

    /// 次按钮：浅灰底大胶囊（审批 Reject 同款）。
    func secondaryCapsule() -> some View {
        self
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Palette.control, in: Capsule())
    }
}

/// 贴合内容的 bottom sheet 修饰器：量内容高度定 detent，内容超屏可滚动。
private struct FittedSheetModifier: ViewModifier {
    @State private var height: CGFloat = 320

    func body(content: Content) -> some View {
        ScrollView {
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(height)])
        .presentationCornerRadius(36)
        .presentationDragIndicator(.hidden)
        .presentationBackground(Palette.background)
    }
}

/// 状态圆点：运行中绿、等待中琥珀、空闲灰。
struct StatusDot: View {
    enum Kind { case running, waiting, idle }
    let kind: Kind

    var body: some View {
        Circle()
            .fill(kind == .running ? Palette.running
                    : kind == .waiting ? Palette.waiting : Palette.faint)
            .frame(width: 8, height: 8)
    }
}

/// FishPocket 智能体 Tab 的幽灵图标（原版同款造型，自己画的 Shape，不用 emoji）。
struct GhostShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let r = w / 2
        p.move(to: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: r))
        p.addArc(center: CGPoint(x: r, y: r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: w, y: h))
        // 底部三道波浪（从右往左，每道向上拱）。
        let waveW = w / 3
        for i in 0..<3 {
            let x0 = w - CGFloat(i) * waveW
            let x1 = w - CGFloat(i + 1) * waveW
            p.addQuadCurve(to: CGPoint(x: x1, y: h),
                           control: CGPoint(x: (x0 + x1) / 2, y: h - waveW * 0.45))
        }
        p.closeSubpath()
        return p
    }
}

struct GhostIcon: View {
    var body: some View {
        ZStack {
            GhostShape().fill(Palette.ink)
            HStack(spacing: 6) {
                Circle().fill(Palette.background).frame(width: 3.5, height: 3.5)
                Circle().fill(Palette.background).frame(width: 3.5, height: 3.5)
            }
            .offset(y: -3)
        }
        .frame(width: 24, height: 24)
    }
}
