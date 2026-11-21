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
    @State private var showingPhotoPicker = false
    @State private var showingDocumentPicker = false
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    private var trimmedEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSend: Bool {
        guard !trimmedEmpty || !attachments.isEmpty else { return false }
        // Offline: plain text queues to the relay mailbox; files cannot.
        if !isOnline && !attachments.isEmpty { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Palette.danger)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
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
                plusButton
                HStack(alignment: .bottom, spacing: 0) {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .font(.body)
                        .lineLimit(1...8)
                        .focused($fieldFocused)
                        .padding(.leading, 18)
                        .padding(.vertical, 6)
                    micButton
                    trailingButton
                }
                .padding(.trailing, 6)
                .frame(minHeight: 54)
                .background(Palette.bubbleAgent, in: RoundedRectangle(cornerRadius: 24))
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
        Menu {
            Button {
                showingPhotoPicker = true
            } label: {
                Label(L("照片"), systemImage: "photo.on.rectangle")
            }
            Button {
                showingDocumentPicker = true
            } label: {
                Label(L("文件"), systemImage: "folder")
            }
            if UIPasteboard.general.hasImages || UIPasteboard.general.hasURLs {
                Button {
                    pasteFromClipboard()
                } label: {
                    Label(L("粘贴"), systemImage: "doc.on.clipboard")
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Palette.text)
                .frame(width: 54, height: 54)
                .background(Palette.bubbleAgent, in: Circle())
        }
    }

    private var micButton: some View {
        Button {
            // Phase 1: focus the field so the keyboard's dictation mic is
            // one tap away. Voice engines are a Phase 2 item.
            fieldFocused = true
        } label: {
            Image(systemName: "mic")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.secondary)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var trailingButton: some View {
        if !trimmedEmpty || !attachments.isEmpty {
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(canSend ? Palette.onAccent : Palette.tertiary)
                    .frame(width: 34, height: 34)
                    .background(canSend ? Palette.accentFill : Palette.accentDim, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        } else if isWorking {
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.onAccent)
                    .frame(width: 34, height: 34)
                    .background(Palette.accentFill, in: Circle())
            }
            .buttonStyle(.plain)
        } else {
            // Idle, empty, no files: no trailing action in Phase 1
            // (voice calls are a later phase).
            Color.clear.frame(width: 0, height: 34)
        }
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
