import SwiftUI

/// 液态玻璃（共用）：iOS 26 真玻璃 + 提亮 + 顶部高光描边。
/// 纯黑底上素玻璃几乎看不见——玻璃后面没东西可折射，看着就是黑块。
/// 所以 tint 提亮玻璃体，渐变描边做液态边缘高光，浮在内容上时折射才看得见。
extension View {
    func liquidGlass<S: Shape>(_ shape: S) -> some View {
        self
            .glassEffect(.regular.tint(.white.opacity(0.10)), in: shape)
            .overlay(shape.stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.55), Color.white.opacity(0.12), Color.white.opacity(0.04)],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1))
    }

    /// 可交互的液态玻璃（按钮用，按下去有玻璃形变）。
    func liquidGlassInteractive<S: Shape>(_ shape: S) -> some View {
        self
            .glassEffect(.regular.interactive().tint(.white.opacity(0.10)), in: shape)
            .overlay(shape.stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.55), Color.white.opacity(0.12), Color.white.opacity(0.04)],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1))
    }
}
