import SwiftUI

/// FishPocket 配色（Design/Palette.swift）：浅色为默认，深色只在系统深色模式下用。
/// 取值逐项核对过 FishPocket 源码 Assets.xcassets 的 Contents.json。
enum Palette {
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { trait in
            UIColor(trait.userInterfaceStyle == .dark ? Color(hex: dark) : Color(hex: light))
        })
    }

    /// 主背景：#FFFFFF / #0C0C0D
    static let background = adaptive(light: 0xFFFFFF, dark: 0x0C0C0D)
    /// 主字色：#0C0C0D / #F2F2F3
    static let ink = adaptive(light: 0x0C0C0D, dark: 0xF2F2F3)
    /// 深色块上的字：#FFFFFF / #0C0C0D
    static let onInk = adaptive(light: 0xFFFFFF, dark: 0x0C0C0D)
    /// 次要文字：#6B6B72 / #9A9AA0
    static let secondary = adaptive(light: 0x6B6B72, dark: 0x9A9AA0)
    /// 最淡文字：#A3A3AA / #6E6E74
    static let faint = adaptive(light: 0xA3A3AA, dark: 0x6E6E74)
    /// 输入框底：#F3F3F4 / #1A1A1C
    static let field = adaptive(light: 0xF3F3F4, dark: 0x1A1A1C)
    /// 分组底：#F5F5F6 / #141416
    static let grouped = adaptive(light: 0xF5F5F6, dark: 0x141416)
    /// 用户气泡：#ECECEE / #222225
    static let bubble = adaptive(light: 0xECECEE, dark: 0x222225)
    /// 控件底（圆形按钮、次按钮）：#E5E5E8 / #2A2A2E
    static let control = adaptive(light: 0xE5E5E8, dark: 0x2A2A2E)
    /// 描边：#E3E3E6 / #2E2E32
    static let stroke = adaptive(light: 0xE3E3E6, dark: 0x2E2E32)
    /// 运行中（绿）：#12A06A / #3DD68C
    static let running = adaptive(light: 0x12A06A, dark: 0x3DD68C)
    /// 等待中（琥珀）：#D98A00 / #F5A524
    static let waiting = adaptive(light: 0xD98A00, dark: 0xF5A524)
    /// 强调（FishPocket Spot 橙红）：#F2552C / #FF6B42
    static let spot = adaptive(light: 0xF2552C, dark: 0xFF6B42)
    /// 遮罩：黑 25% / 黑 55%
    static let scrim = Color(UIColor { trait in
        UIColor.black.withAlphaComponent(trait.userInterfaceStyle == .dark ? 0.55 : 0.25)
    })
    /// Diff 新增行底：#E6F4EE / #123326
    static let diffAddBackground = adaptive(light: 0xE6F4EE, dark: 0x123326)
    /// Diff 删除行底：#FDECEA / #3A1A17
    static let diffDeleteBackground = adaptive(light: 0xFDECEA, dark: 0x3A1A17)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}
