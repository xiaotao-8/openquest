import SwiftUI

/// The 8 avatar shapes (UI_SPEC §2.2): blob, pebble, squircle, tablet,
/// wedge, hex, cloud, teardrop. Approximations of the originals' paths;
/// squircle uses a continuous corner radius.
enum AvatarShape: String, CaseIterable {
    case blob, pebble, squircle, tablet, wedge, hex, cloud, teardrop

    func path(in rect: CGRect) -> Path {
        switch self {
        case .blob:
            return BlobShape().path(in: rect)
        case .pebble:
            return PebbleShape().path(in: rect)
        case .squircle:
            return RoundedRectangle(cornerRadius: rect.width * 0.28, style: .continuous).path(in: rect)
        case .tablet:
            return Capsule().path(in: rect)
        case .wedge:
            return WedgeShape().path(in: rect)
        case .hex:
            return HexShape().path(in: rect)
        case .cloud:
            return CloudShape().path(in: rect)
        case .teardrop:
            return TeardropShape().path(in: rect)
        }
    }
}

/// Organic asymmetric blob: four bezier lobes with different radii.
struct BlobShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: w * 0.50, y: h * 0.02))
        path.addCurve(to: CGPoint(x: w * 0.98, y: h * 0.42),
                      control1: CGPoint(x: w * 0.78, y: h * 0.02),
                      control2: CGPoint(x: w * 0.98, y: h * 0.18))
        path.addCurve(to: CGPoint(x: w * 0.82, y: h * 0.96),
                      control1: CGPoint(x: w * 0.98, y: h * 0.66),
                      control2: CGPoint(x: w * 0.96, y: h * 0.88))
        path.addCurve(to: CGPoint(x: w * 0.18, y: h * 0.92),
                      control1: CGPoint(x: w * 0.68, y: h * 1.04),
                      control2: CGPoint(x: w * 0.38, y: h * 1.02))
        path.addCurve(to: CGPoint(x: w * 0.02, y: h * 0.38),
                      control1: CGPoint(x: w * 0.02, y: h * 0.80),
                      control2: CGPoint(x: w * 0.02, y: h * 0.60))
        path.addCurve(to: CGPoint(x: w * 0.50, y: h * 0.02),
                      control1: CGPoint(x: w * 0.02, y: h * 0.16),
                      control2: CGPoint(x: w * 0.22, y: h * 0.02))
        path.closeSubpath()
        return path
    }
}

/// A pebble: a rounded rect with one corner pulled in.
struct PebbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: w * 0.30, y: h * 0.04))
        path.addCurve(to: CGPoint(x: w * 0.94, y: h * 0.30),
                      control1: CGPoint(x: w * 0.62, y: h * 0.00),
                      control2: CGPoint(x: w * 0.96, y: h * 0.08))
        path.addCurve(to: CGPoint(x: w * 0.86, y: h * 0.94),
                      control1: CGPoint(x: w * 0.92, y: h * 0.58),
                      control2: CGPoint(x: w * 0.94, y: h * 0.78))
        path.addCurve(to: CGPoint(x: w * 0.14, y: h * 0.90),
                      control1: CGPoint(x: w * 0.72, y: h * 1.04),
                      control2: CGPoint(x: w * 0.36, y: h * 1.00))
        path.addCurve(to: CGPoint(x: w * 0.06, y: h * 0.28),
                      control1: CGPoint(x: w * 0.02, y: h * 0.76),
                      control2: CGPoint(x: w * 0.02, y: h * 0.52))
        path.addCurve(to: CGPoint(x: w * 0.30, y: h * 0.04),
                      control1: CGPoint(x: w * 0.10, y: h * 0.10),
                      control2: CGPoint(x: w * 0.16, y: h * 0.04))
        path.closeSubpath()
        return path
    }
}

/// A wedge: a rounded triangle pointing up-right.
struct WedgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        let r: CGFloat = w * 0.12
        path.move(to: CGPoint(x: w * 0.50, y: h * 0.04))
        path.addQuadCurve(to: CGPoint(x: w * 0.96, y: h * 0.86),
                          control: CGPoint(x: w * 0.86, y: h * 0.52))
        path.addQuadCurve(to: CGPoint(x: w * 0.04, y: h * 0.86),
                          control: CGPoint(x: w * 0.50, y: h * 0.98 - r))
        path.addQuadCurve(to: CGPoint(x: w * 0.50, y: h * 0.04),
                          control: CGPoint(x: w * 0.14, y: h * 0.52))
        path.closeSubpath()
        return path
    }
}

struct HexShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX, cy = rect.midY, r = rect.width / 2
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3 - .pi / 2
            let point = CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// A cloud: three overlapping arcs on a flat base.
struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.addArc(center: CGPoint(x: w * 0.32, y: h * 0.58), radius: w * 0.26,
                    startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        path.addArc(center: CGPoint(x: w * 0.55, y: h * 0.42), radius: w * 0.28,
                    startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        path.addArc(center: CGPoint(x: w * 0.74, y: h * 0.60), radius: w * 0.22,
                    startAngle: .degrees(270), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: w * 0.90, y: h * 0.86))
        path.addLine(to: CGPoint(x: w * 0.10, y: h * 0.86))
        path.closeSubpath()
        return path
    }
}

/// A teardrop: a circle with the top pulled to a point.
struct TeardropShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: w * 0.50, y: h * 0.02))
        path.addCurve(to: CGPoint(x: w * 0.98, y: h * 0.58),
                      control1: CGPoint(x: w * 0.78, y: h * 0.22),
                      control2: CGPoint(x: w * 0.98, y: h * 0.36))
        path.addCurve(to: CGPoint(x: w * 0.50, y: h * 0.98),
                      control1: CGPoint(x: w * 0.98, y: h * 0.82),
                      control2: CGPoint(x: w * 0.78, y: h * 0.98))
        path.addCurve(to: CGPoint(x: w * 0.02, y: h * 0.58),
                      control1: CGPoint(x: w * 0.22, y: h * 0.98),
                      control2: CGPoint(x: w * 0.02, y: h * 0.82))
        path.addCurve(to: CGPoint(x: w * 0.50, y: h * 0.02),
                      control1: CGPoint(x: w * 0.02, y: h * 0.36),
                      control2: CGPoint(x: w * 0.22, y: h * 0.22))
        path.closeSubpath()
        return path
    }
}

/// A bot/group avatar: coloured shape with the first letter of the name.
/// Falls back to a blue blob when the colour or shape name is unknown.
struct AvatarView: View {
    var name: String
    var colorName: String
    var shapeName: String
    var size: CGFloat

    init(bot: Bot, size: CGFloat) {
        name = bot.name
        colorName = bot.avatarColor
        shapeName = bot.avatarShape
        self.size = size
    }

    init(name: String, color: String, shape: String, size: CGFloat) {
        self.name = name
        colorName = color
        shapeName = shape
        self.size = size
    }

    var body: some View {
        let shape = AvatarShape(rawValue: shapeName) ?? .blob
        let color = Palette.avatarColor(named: colorName)
        ZStack {
            shape.path(in: CGRect(x: 0, y: 0, width: size, height: size))
                .fill(color)
            Text(firstLetter)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    private var firstLetter: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }
}
