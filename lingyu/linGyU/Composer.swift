import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// One file waiting to be sent. Uploaded on send; the 100 MB limit is
/// enforced at pick time (the app knows it, the UI never shows the number
/// as a setting — it only errors when exceeded).
struct PendingAttachment: Identifiable {
    var id = UUID()
    var name: String
    var data: Data
    var isImage: Bool

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }
}

struct Composer: View {
    var bot: Bot
    @Binding var text: String
    var isWorking: Bool
    var isOnline: Bool
    var onSend: (String, [PendingAttachment]) -> Void
    var onStop: () -> Void

    @State private var attachments: [PendingAttachment] = []
    @State private var showingCallLater = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var trimmedEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSend: Bool {
        guard !trimmedEmpty || !attachments.isEmpty else { return false }
        // Offline: plain text queues to the relay mailbox; files cannot.
        if !isOnline && !attachments.isEmpty { return false }
        return true
    }

    /// The one-line field's height is 54pt: max(22 + 2·10, 34) + 2·6,
    /// the same as the + circle beside it.

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Palette.danger)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
            HStack(alignment: .bottom, spacing: 8) {
                plusButton
                VStack(alignment: .leading, spacing: 0) {
                    if !attachments.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(attachments) { attachment in
                                    AttachmentChip(attachment: attachment) {
                                        attachments.removeAll { $0.id == attachment.id }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.top, 8)
                    }
                    HStack(alignment: .bottom, spacing: 8) {
                        TextField(placeholder, text: $text, axis: .vertical)
                            .font(.body)
                            .textFieldStyle(.plain)
                            .lineLimit(1...8)
                            .focused($fieldFocused)
                            .padding(.vertical, 10)
                        micButton
                            .padding(.bottom, max(0, (22 + 2 * 10 - 34) / 2))
                        trailingButton
                            .padding(.bottom, max(0, (22 + 2 * 10 - 34) / 2))
                    }
                    .padding(.leading, 18)
                    .padding(.trailing, 6)
                    .padding(.vertical, 6)
                }
                .glass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $showingPhotoPicker) {
            PhotoPicker { images in
                addImages(images)
            }
        }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker { urls in
                addFiles(urls)
            }
        }
        .codyncDialog(isPresented: $showingCallLater, title: L("通话稍后推出"), message: L("语音通话会在后续阶段加入，现在还不能打电话。"), actions: [
            CodyncDialogAction(title: L("好"), action: {}),
        ])
    }

    private var placeholder: String {
        if bot.isGroup {
            return L("问大家 · @ 只问一个智能体")
        }
        if isWorking {
            return L("给 %@ 排一条消息", bot.name)
        }
        return L("问 %@", bot.name)
    }

    private var plusButton: some View {
        DropdownMenu {
            var items = [
                MenuItem(L("照片"), icon: "photo.on.rectangle") { showingPhotoPicker = true },
                MenuItem(L("文件"), icon: "folder") { showingDocumentPicker = true },
            ]
            if UIPasteboard.general.hasImages || UIPasteboard.general.hasURLs {
                items.append(MenuItem(L("粘贴"), icon: "doc.on.clipboard") { pasteFromClipboard() })
            }
            return items
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Palette.text)
                .frame(width: 54, height: 54)
                .glass(in: Circle())
        }
    }

    /// Dictation, beside send / call: a light circle with its engine menu.
    /// Phase 1 has one engine — the keyboard's dictation, one tap away —
    /// so the mic focuses the field; voice engines are a later phase.
    private var micButton: some View {
        HStack(spacing: 0) {
            Button {
                fieldFocused = true
            } label: {
                Image(systemName: "mic")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
            }
            .buttonStyle(PressScale())
            .accessibilityLabel(L("听写"))
            DictationEngineMenu(height: 34)
        }
        .background(Palette.bubbleAgent, in: Capsule())
    }

    private enum Trailing: Equatable { case stop, call, send }

    /// One button that morphs between call, send and stop: its symbol
    /// replaces itself, its fill crossfades and the capsule narrows to a
    /// circle, so switching never pops.
    private var trailing: Trailing {
        if isWorking, trimmedEmpty, attachments.isEmpty { return .stop }
        if trimmedEmpty, attachments.isEmpty { return .call }
        return .send
    }

    @ViewBuilder
    private var trailingButton: some View {
        let state = trailing
        let enabled = state != .send || canSend
        let (symbol, label, size): (String, String, CGFloat) = switch state {
        case .stop: ("stop.fill", L("停止"), 12)
        case .call: ("waveform", L("通话"), 15)
        case .send: ("arrow.up", L("发送"), 14)
        }
        let fill: Color = switch state {
        case .send: canSend ? Palette.accentFill : Palette.accentDim
        case .stop, .call: Palette.accentFill
        }
        let ink: Color = switch state {
        case .send: canSend ? Palette.onAccent : Palette.tertiary
        case .stop, .call: Palette.onAccent
        }
        Button {
            switch state {
            case .stop: onStop()
            case .call: showingCallLater = true
            case .send: send()
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(ink)
                .frame(width: state == .call ? 34 * 1.35 : 34, height: 34)
                .background(fill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .disabled(!enabled)
        .accessibilityLabel(label)
        .animation(Motion.reduced(Motion.morph, reduceMotion), value: state)
        .animation(Motion.reduced(Motion.morph, reduceMotion), value: canSend)
    }

    private func send() {
        let message = text
        let files = attachments
        text = ""
        attachments.removeAll()
        onSend(message, files)
    }

    private func addImages(_ images: [(name: String, data: Data)]) {
        for image in images.prefix(10 - attachments.count) {
            guard image.data.count <= 100 * 1024 * 1024 else {
                errorMessage = L("%@ 超过 100 MB。", image.name)
                continue
            }
            attachments.append(PendingAttachment(name: image.name, data: image.data, isImage: true))
        }
    }

    private func addFiles(_ urls: [URL]) {
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { continue }
            guard data.count <= 100 * 1024 * 1024 else {
                errorMessage = L("%@ 超过 100 MB。", url.lastPathComponent)
                continue
            }
            attachments.append(PendingAttachment(name: url.lastPathComponent, data: data, isImage: false))
        }
    }

    private func pasteFromClipboard() {
        if let image = UIPasteboard.general.image,
           let data = image.jpegData(compressionQuality: 0.9) {
            addImages([(name: "pasted.jpg", data: data)])
        } else if let url = UIPasteboard.general.url {
            text += url.absoluteString
        }
    }
}

struct AttachmentChip: View {
    var attachment: PendingAttachment
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if attachment.isImage, let image = UIImage(data: attachment.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "doc")
                    .foregroundStyle(Palette.secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(attachment.name)
                    .font(.caption)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text(attachment.sizeText)
                    .font(.caption2)
                    .foregroundStyle(Palette.secondary)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Palette.bubbleAgent, in: Capsule())
    }
}

// MARK: - Dictation engine menu

/// Beside the composer's mic, in its capsule: which speech dictation uses.
/// Phase 1 has one engine — the device's own dictation, reached through
/// the keyboard — so the menu lists just it; providers come later.
struct DictationEngineMenu: View {
    let height: CGFloat
    @AppStorage("cn.lingyu.dictationEngine") private var engine = "device"

    var body: some View {
        DropdownMenu {
            [MenuItem(L("设备自带听写"), selected: engine == "device") { engine = "device" }]
        } label: {
            Image(systemName: "chevron.up")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.secondary)
                .frame(width: 14, height: height)
                .padding(.trailing, 6)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(L("听写引擎"))
    }
}

// MARK: - Pickers

struct PhotoPicker: UIViewControllerRepresentable {
    var onPick: ([(name: String, data: Data)]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 10
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var onPick: ([(name: String, data: Data)]) -> Void

        init(onPick: @escaping ([(name: String, data: Data)]) -> Void) {
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            var images: [(name: String, data: Data)] = []
            let group = DispatchGroup()
            for (index, result) in results.enumerated() {
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    defer { group.leave() }
                    guard let image = object as? UIImage,
                          let data = image.jpegData(compressionQuality: 0.9) else { return }
                    let timestamp = Int(Date().timeIntervalSince1970)
                    images.append((name: "photo-\(timestamp)-\(index).jpg", data: data))
                }
            }
            group.notify(queue: .main) {
                self.onPick(images)
            }
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
