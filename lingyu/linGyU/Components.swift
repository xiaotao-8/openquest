import SwiftUI

// MARK: - Motion

/// The original's motion constants, so presses, tabs and layout changes
/// feel the same. With Reduce Motion on, durations drop to 0.
enum Motion {
    static let hover = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.12)
    static let fade = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.12)
    static let press = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.05)
    static let morph = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.2)
    static let layout = Animation.spring(duration: 0.3, bounce: 0)
    static let conversation = Animation.spring(duration: 0.42, bounce: 0)
    static let activityPhase = Animation.spring(duration: 0.6, bounce: 0.3)
    static let pressScale: CGFloat = 0.98

    static func reduced(_ animation: Animation, _ reduce: Bool) -> Animation? {
        reduce ? nil : animation
    }

    @MainActor static func animate(_ change: () -> Void) {
        let reduce = UIAccessibility.isReduceMotionEnabled
        withAnimation(reduced(layout, reduce), change)
    }
}

/// Press: shrink to 98% in 50ms, spring back.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Motion.pressScale : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Palette.onAccent)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(Palette.accentFill, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(Palette.bubbleUser, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(Palette.danger, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == DangerButtonStyle {
    static var danger: DangerButtonStyle { DangerButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// A full-width primary action. No fixed height: the original's
/// StyledButton has no minHeight (~44pt from its padding).
struct PrimaryActionButton: View {
    var title: String
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.primary)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Palette.secondary)
            .frame(width: 36, height: 36)
            .background(
                configuration.isPressed ? Palette.text.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var iconButton: IconButtonStyle { IconButtonStyle() }
}

// MARK: - Switch

/// The Codync switch: the label on the left, the switch on the right.
/// Black/white track, never green.
struct CodyncSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 0)
            Button {
                configuration.isOn.toggle()
            } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? Palette.accentFill : Palette.bubbleUser)
                        .frame(width: 34, height: 20)
                    Circle()
                        .fill(configuration.isOn ? Palette.onAccent : .white)
                        .frame(width: 16, height: 16)
                        .padding(2)
                }
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.4)
    }
}

extension ToggleStyle where Self == CodyncSwitchStyle {
    static var codync: CodyncSwitchStyle { CodyncSwitchStyle() }
}

// MARK: - Segmented / tabs

struct SegmentedChoice<Value: Hashable & Equatable>: View {
    var options: [(value: Value, title: String)]
    @Binding var selection: Value
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(selection == option.value ? Palette.text : Palette.secondary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background {
                            if selection == option.value {
                                Capsule()
                                    .fill(Palette.background)
                                    .matchedGeometryEffect(id: "segmented", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Palette.bubbleUser, in: Capsule())
    }
}

struct TabChoice: View {
    var titles: [String]
    @Binding var selection: Int
    var small: Bool = false
    @Namespace private var namespace

    private func tabs(font: Font) -> some View {
        HStack(spacing: 2) {
            ForEach(titles.indices, id: \.self) { index in
                Button {
                    withAnimation(Motion.hover) { selection = index }
                } label: {
                    Text(titles[index])
                        .font(font)
                        .foregroundStyle(selection == index ? Palette.text : Palette.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if selection == index {
                                Capsule()
                                    .fill(Palette.bubbleAgent)
                                    .matchedGeometryEffect(id: "TabChoice", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    var body: some View {
        // When they all fit, show them all; otherwise scroll.
        ViewThatFits(in: .horizontal) {
            tabs(font: small ? .footnote : .subheadline)
            ScrollView(.horizontal, showsIndicators: false) {
                tabs(font: small ? .footnote : .subheadline)
            }
        }
    }
}

// MARK: - Search

struct SearchField: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.secondary)
            TextField(placeholder, text: $text)
                .font(.body)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Palette.bubbleAgent, in: Capsule())
    }
}

// MARK: - Cards / rows

struct CardSection<Content: View>: View {
    var title: String?
    var footer: String?
    var outlined: Bool = false
    var accessory: AnyView?
    @ViewBuilder var content: Content

    init(title: String? = nil, footer: String? = nil, outlined: Bool = false, accessory: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.outlined = outlined
        self.accessory = accessory
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    accessory
                }
                .padding(.leading, 2)
            }
            if outlined {
                VStack(spacing: 0) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Palette.border, lineWidth: 1)
                )
            } else {
                VStack(spacing: 0) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
            }
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(Palette.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CardRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 32, alignment: .leading)
    }
}

struct Hairline: View {
    var body: some View {
        Palette.border
            .frame(height: 1 / UIScreen.main.scale)
            .padding(.horizontal, 16)
    }
}

/// A row with a label and a value. The value is either a string or a view
/// (a picker or a switch). No chevron: it shows, it doesn't go anywhere.
struct ValueRow<Value: View>: View {
    var label: String
    var detail: String?
    var value: Value

    init(label: String, detail: String? = nil, value: String?) where Value == Text {
        self.label = label
        self.detail = detail
        self.value = Text(value ?? "")
            .foregroundStyle(Palette.secondary)
    }

    init(label: String, detail: String? = nil, @ViewBuilder value: () -> Value) {
        self.label = label
        self.detail = detail
        self.value = value()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .foregroundStyle(Palette.text)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Palette.secondary)
                        .lineSpacing(2)
                }
            }
            Spacer(minLength: 12)
            value
        }
    }
}

// MARK: - Headers

struct ScreenHeader: View {
    var title: String
    var leading: AnyView?
    var trailing: AnyView?

    init(title: String, leading: AnyView? = nil, trailing: AnyView? = nil) {
        self.title = title
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.text)
            HStack {
                leading ?? AnyView(Color.clear.frame(width: 36, height: 36))
                Spacer()
                trailing ?? AnyView(Color.clear.frame(width: 36, height: 36))
            }
        }
        .frame(height: 52)
        .padding(.horizontal, 12)
        .background(Palette.background)
    }
}

struct ModalHeader: View {
    var title: String
    var trailing: AnyView?
    var onClose: () -> Void

    init(title: String, trailing: AnyView? = nil, onClose: @escaping () -> Void) {
        self.title = title
        self.trailing = trailing
        self.onClose = onClose
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
            Spacer()
            if let trailing {
                trailing
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 56)
        .padding(.leading, 20)
        .padding(.trailing, 12)
    }
}

// MARK: - Sheet / dialog wrappers

extension View {
    /// The sanctioned sheet path (grabber visible, swipe to dismiss).
    func codyncSheet<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        sheet(isPresented: isPresented) {
            content()
                .presentationDragIndicator(.visible)
        }
    }

    /// A custom confirmation dialog (replaces system alert/confirmationDialog).
    func codyncDialog(isPresented: Binding<Bool>, title: String, message: String, actions: [CodyncDialogAction]) -> some View {
        overlay {
            if isPresented.wrappedValue {
                CodyncDialogView(title: title, message: message, actions: actions) {
                    isPresented.wrappedValue = false
                }
            }
        }
    }
}

struct CodyncDialogAction: Identifiable {
    var id = UUID()
    var title: String
    var isDestructive: Bool = false
    var action: () -> Void
}

struct CodyncDialogView: View {
    var title: String
    var message: String
    var actions: [CodyncDialogAction]
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Palette.text)
                Text(message)
                    .font(.body)
                    .foregroundStyle(Palette.secondary)
                VStack(spacing: 8) {
                    ForEach(actions) { item in
                        dialogActionButton(item)
                    }
                }
            }
            .padding(20)
            .background(Palette.background, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)
        }
    }

    /// The two branches must stay separate: `.danger` is DangerButtonStyle and
    /// `.secondary` is SecondaryButtonStyle, and a ternary over two different
    /// concrete styles does not type-check (Build #5: PrimitiveButtonStyle
    /// has no member 'danger'/'secondary').
    @ViewBuilder
    private func dialogActionButton(_ item: CodyncDialogAction) -> some View {
        let button = Button {
            onDismiss()
            item.action()
        } label: {
            Text(item.title)
                .frame(maxWidth: .infinity)
        }
        if item.isDestructive {
            button.buttonStyle(.danger)
        } else {
            button.buttonStyle(.secondary)
        }
    }
}

// MARK: - Spinner

struct Spinner: View {
    var size: CGFloat

    var body: some View {
        ProgressView()
            .controlSize(.small)
            .frame(width: size, height: size)
    }
}

/// The symbol for a file by its extension (original AttachmentIcon):
/// image → photo, audio → waveform, pdf → doc.richtext,
/// zip/gz/tar/7z → doc.zipper, mov/mp4/m4v → film, else doc.
enum AttachmentIcon {
    static func symbol(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "bmp"].contains(ext) { return "photo" }
        if ["mp3", "m4a", "wav", "aac"].contains(ext) { return "waveform" }
        switch ext {
        case "pdf": return "doc.richtext"
        case "zip", "gz", "tar", "7z": return "doc.zipper"
        case "mov", "mp4", "m4v": return "film"
        default: return "doc"
        }
    }
}

// MARK: - Choice picker

/// One of a few choices, picked from a system menu: the value and a
/// down chevron in an outlined pill. Long option labels wrap onto two
/// lines. Pass `disabled` for options that only say something.
struct ChoicePicker<ID: Hashable>: View {
    let selection: Binding<ID>
    let options: [(id: ID, label: String)]
    var disabled: Set<ID> = []
    var fill: Color = .clear
    var fitsAvailableWidth: Bool = false
    var image: ((ID) -> Image?)? = nil

    var body: some View {
        let selected = options.first { $0.id == selection.wrappedValue }
        DropdownMenu(items: {
            options.map { option in
                MenuItem(option.label, image: image?(option.id), selected: option.id == selection.wrappedValue,
                         enabled: !disabled.contains(option.id)) {
                    selection.wrappedValue = option.id
                }
            }
        }) {
            HStack(spacing: 6) {
                if let image = selected.flatMap({ image?($0.id) }) {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                }
                Text(selected?.label ?? "")
                    .font(.body)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: fitsAvailableWidth ? .infinity : nil, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Palette.border, lineWidth: 1))
        }
    }
}

/// A switch row: a label, an optional explanation, and the switch on the
/// right, for use inside a card.
struct SwitchRow: View {
    var label: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .foregroundStyle(Palette.text)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Palette.secondary)
                        .lineSpacing(2)
                }
            }
        }
        .toggleStyle(.codync)
    }
}

// MARK: - Glass & pills

extension View {
    /// The app's glass: liquid glass on iOS 26, ultra-thin material below.
    func glass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            return AnyView(self.glassEffect(.regular, in: shape))
        } else {
            return AnyView(self.background(.ultraThinMaterial, in: shape))
        }
    }

    /// A small pill: the shape used for chips, badges and the composer capsule.
    func pill() -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Palette.bubbleAgent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// The same pill, outlined instead of filled.
    func outlinedPill() -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Palette.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Palette.border, lineWidth: 1))
    }

    /// A card outline: a rounded rectangle with a hairline border.
    func outlinedCard(cornerRadius: CGFloat = 14, dashed: Bool = false) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Palette.border, style: StrokeStyle(lineWidth: 1, dash: dashed ? [4, 3] : []))
        )
    }
}
