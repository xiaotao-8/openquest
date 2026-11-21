import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    static func dynamic(light: Color, dark: Color) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

/// Codync's exact palette (UI_SPEC §2.1). Light / dark hex per token.
enum Palette {
    static let background = Color.dynamic(light: Color(hex: "FFFFFF"), dark: Color(hex: "0A0A0A"))
    static let surface = Color.dynamic(light: Color(hex: "F4F4F4"), dark: Color(hex: "141414"))
    static let bubbleAgent = Color.dynamic(light: Color(hex: "F0F0F0"), dark: Color(hex: "1C1C1C"))
    static let bubbleUser = Color.dynamic(light: Color(hex: "E2E2E2"), dark: Color(hex: "363636"))
    static let border = Color.dynamic(light: Color(hex: "E6E6E6"), dark: Color(hex: "262626"))
    static let text = Color.dynamic(light: Color(hex: "141414"), dark: Color(hex: "F2F2F2"))
    static let secondary = Color.dynamic(light: Color(hex: "6B6B6B"), dark: Color(hex: "9A9A9A"))
    static let tertiary = Color.dynamic(light: Color(hex: "767676"), dark: Color(hex: "929292"))
    static let accentFill = Color.dynamic(light: Color(hex: "000000"), dark: Color(hex: "FFFFFF"))
    static let accent = Color.dynamic(light: Color(hex: "000000"), dark: Color(hex: "FFFFFF"))
    static let onAccent = Color.dynamic(light: Color(hex: "FFFFFF"), dark: Color(hex: "000000"))
    static let accentDim = Color.dynamic(light: Color(hex: "D9D9D9"), dark: Color(hex: "333333"))
    static let danger = Color.dynamic(light: Color(hex: "C23A2B"), dark: Color(hex: "F0A7A7"))
    static let warning = Color(hex: "F0A030")
    static let onWarning = Color(hex: "000000")
    static let attention = Color.dynamic(light: Color(hex: "936000"), dark: Color(hex: "ECAF52"))
    static let codeBackground = Color.dynamic(light: Color(hex: "F4F4F4"), dark: Color(hex: "111111"))
    static let added = Color.dynamic(light: Color(hex: "2E7D32"), dark: Color(hex: "8FD18B"))
    static let removed = Color.dynamic(light: Color(hex: "C62828"), dark: Color(hex: "F0A7A7"))

    /// The 11 avatar colours, in the order the picker shows them.
    static let avatarColors: [(name: String, color: Color)] = [
        ("black", Color(hex: "2B2B2B")),
        ("brown", Color(hex: "936439")),
        ("red", Color(hex: "FF263C")),
        ("orange", Color(hex: "FF6700")),
        ("yellow", Color(hex: "FF9800")),
        ("green", Color(hex: "00C972")),
        ("cyan", Color(hex: "00BCA6")),
        ("blue", Color(hex: "1084FE")),
        ("violet", Color(hex: "9159FE")),
        ("magenta", Color(hex: "FF309B")),
        ("gray", Color(hex: "777777")),
    ]

    static func avatarColor(named name: String) -> Color {
        avatarColors.first { $0.name == name }?.color ?? Color(hex: "1084FE")
    }
}
