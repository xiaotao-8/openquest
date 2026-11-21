import SwiftUI

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

extension ButtonStyle where Self == DangerButtonStyle {
    static var danger: DangerButtonStyle { DangerButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// A full-width primary action (min height 50).
struct PrimaryActionButton: View {
    var title: String
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
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

/// The Codync switch: black/white track, never green.
struct CodyncSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(titles.indices, id: \.self) { index in
                    Button {
                        selection = index
                    } label: {
                        Text(titles[index])
                            .font(.subheadline)
                            .foregroundStyle(selection == index ? Palette.text : Palette.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                selection == index ? Palette.bubbleAgent : Color.clear,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
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
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
            }
            if outlined {
                VStack(spacing: 0) {
                    content
                }
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Palette.border, lineWidth: 1)
                )
            } else {
                VStack(spacing: 0) {
                    content
                }
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
            }
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(Palette.secondary)
                    .lineSpacing(2)
                    .padding(.horizontal, 2)
            }
        }
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

struct ValueRow: View {
    var label: String
    var detail: String?
    var value: String?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .foregroundStyle(Palette.text)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Palette.secondary)
                        .lineSpacing(2)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            if let value {
                Text(value)
                    .foregroundStyle(Palette.secondary)
            }
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
                        Button {
                            onDismiss()
                            item.action()
                        } label: {
                            Text(item.title)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(item.isDestructive ? .danger : .secondary)
                    }
                }
            }
            .padding(20)
            .background(Palette.background, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)
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
