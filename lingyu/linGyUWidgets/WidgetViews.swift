import SwiftUI

/// The extension's own palette and avatar: the main app's `Palette` and
/// `CharacterAvatar` are not part of this target. The hex values are the
/// app's own values (see the plan §1.3), so the widgets match the
/// in-app gallery cards that render the same data.
extension Color {
    init(hex: Int) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// A color that follows the system appearance, from its light/dark hex.
    init(light: Int, dark: Int) {
        self.init(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light))
        })
    }
}

enum WidgetPalette {
    static let text = Color(light: 0x141414, dark: 0xF2F2F2)
    static let secondary = Color(light: 0x6B6B6B, dark: 0x9A9A9A)
    static let tertiary = Color(light: 0x9A9A9A, dark: 0x6B6B6B)
    static let surface = Color(light: 0xF4F4F4, dark: 0x141414)
    static let bubble = Color(light: 0xF0F0F0, dark: 0x1C1C1C)
    static let border = Color(light: 0xE6E6E6, dark: 0x262626)
    static let attention = Color(light: 0x936000, dark: 0xECAF52)
    static let danger = Color(light: 0xC23A2B, dark: 0xF0A7A7)
    static let added = Color(light: 0x2E7D32, dark: 0x8FD18B)
    static let onAccent = Color.white

    /// The avatar colours, same 11 names the app uses.
    static func avatarColor(named name: String) -> Color {
        switch name {
        case "black": return Color(hex: 0x2B2B2B)
        case "brown": return Color(hex: 0x936439)
        case "red": return Color(hex: 0xFF263C)
        case "orange": return Color(hex: 0xFF6700)
        case "yellow": return Color(hex: 0xFF9800)
        case "green": return Color(hex: 0x00C972)
        case "cyan": return Color(hex: 0x00BCA6)
        case "blue": return Color(hex: 0x1084FE)
        case "violet": return Color(hex: 0x9159FE)
        case "magenta": return Color(hex: 0xFF309B)
        default: return Color(hex: 0x777777)
        }
    }
}

/// A bot's face in a widget: the first character of its name on its
/// avatar colour. Widgets cannot draw the app's character avatars.
struct WidgetAvatar: View {
    let name: String
    let color: String
    let shape: String
    let size: CGFloat

    init(bot: WidgetBotSnapshot, size: CGFloat) {
        self.name = bot.name
        self.color = bot.avatarColor
        self.shape = bot.avatarShape
        self.size = size
    }

    init(name: String, color: String, shape: String, size: CGFloat) {
        self.name = name
        self.color = color
        self.shape = shape
        self.size = size
    }

    var body: some View {
        Text(String(name.prefix(1)))
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(WidgetPalette.avatarColor(named: color), in: Circle())
    }
}

/// The state word a widget row shows, and its colour: only what needs
/// the user (or failed) stands out.
func widgetStateLabel(needsYou: Bool, working: Bool) -> (label: String, tint: Color) {
    if needsYou { return (L("需要你确认"), WidgetPalette.attention) }
    if working { return (L("进行中"), WidgetPalette.text) }
    return (L("就绪"), WidgetPalette.secondary)
}

/// The unread count pill: amber on black while something waits on the
/// user, else dark on white.
struct WidgetUnreadBadge: View {
    let count: Int
    let waiting: Bool

    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(waiting ? Color.black : Color.white)
                .padding(.horizontal, 6)
                .frame(minHeight: 18)
                .background(waiting ? WidgetPalette.attention : WidgetPalette.text, in: Capsule())
                .accessibilityLabel(L("未读"))
                .accessibilityValue("\(count)")
        }
    }
}

/// An honest empty state: a grey disc and one line. Never a made-up bot.
struct WidgetEmptyState: View {
    let text: String
    let detail: String?

    init(text: String, detail: String? = nil) {
        self.text = text
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Circle()
                .fill(WidgetPalette.secondary.opacity(0.25))
                .frame(width: 26, height: 26)
            Spacer(minLength: 0)
            Text(text)
                .font(.caption)
                .foregroundStyle(WidgetPalette.secondary)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
