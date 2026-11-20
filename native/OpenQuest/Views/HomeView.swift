import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// 首页（FishPocket 新会话页同款）：大标题 + 工作区/模式 pill + 建议 chips + 白色圆角输入框。
/// 发消息直接进“直接聊”（不用先建智能体），首条消息随跳转一起发出去。
struct HomeView: View {
    @EnvironmentObject var store: AppStore
    private func L(_ key: String) -> String { L10n.t(key, lang: store.language) }
    let onOpenSessions: () -> Void
    let onOpenConversation: (ChatDestination) -> Void
    @State private var draft = ""
    @State private var showingModelSheet = false
    @State private var showingImport = false
    @State private var importStatus: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var pendingImage: Data?
    @State private var pendingFileName: String?
    @State private var pendingFileText: String?
    @FocusState private var focused: Bool
    @StateObject private var dictation = SpeechDictation()
    @State private var dictationBase = ""

    private var directAgent: Agent? {
        if let conv = store.conversations.first(where: { $0.title == "直接聊" }),
           let a = conv.memberIds.first.flatMap({ store.agent(id: $0) }) { return a }
        return nil
    }

    private var modelName: String {
        if let a = directAgent {
            let p = store.providers.first { $0.id.uuidString == a.providerKey }
            return p?.models.first { $0.id == a.modelId }?.name ?? L("no_model")
        }
        return store.providers.first?.models.first?.name ?? L("no_model")
    }

    private var modeName: String {
        directAgent?.effort == "high" ? L("deep_thinking") : L("standard_mode")
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespaces).isEmpty
            || pendingImage != nil || pendingFileName != nil
    }

    // 首页建议 chips：按语言取文案（拿不准的语言用英文兜底，见 L10n 表）。
    private var suggestions: [String] {
        [L("suggest_import"), L("suggest_poem"), L("suggest_concept"), L("suggest_plan")]
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            VStack(spacing: 18) {
                Text(L("start_explore"))
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Palette.ink)
                // 两个 pill 竖排居中（原版 home.png）：上工作区、下模式。
                VStack(spacing: 12) {
                    // 工作区：底座只有一个默认工作区，先只展示；多工作区进 FishPocket 核心阶段。
                    Label(L("default_workspace"), systemImage: "folder")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Palette.field, in: Capsule())
                    Menu {
                        Button(L("standard_mode")) { setMode("") }
                        Button(L("deep_thinking")) { setMode("high") }
                    } label: {
                        Label(modeName, systemImage: "cpu")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Palette.field, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            // 建议 chips 沉底：贴在输入框正上方，不再悬在半空（原版 home.png）。
            suggestionChips
                .padding(.bottom, 10)
            composer
                .padding(.horizontal, 16)
                .padding(.bottom, 104)
        }
        .background(Palette.background)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { dictation.refreshAvailability() }
        .onChange(of: dictation.liveText) { _, text in
            draft = dictationBase + text
        }
        .alert(L("voice_permission_title"), isPresented: $dictation.showPermissionAlert) {
            Button(L("go_settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button(L("later"), role: .cancel) {}
        } message: {
            Text(L("voice_permission_msg"))
        }
        .sheet(isPresented: $showingModelSheet) {
            if let a = directAgent { ModelPickerSheet(agent: a) }
        }
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                importStatus = L("import_unreadable")
                return
            }
            let sessions = ChatImport.parse(data)
            if sessions.isEmpty {
                importStatus = L("import_unknown")
                return
            }
            let n = ChatImport.importInto(store, sessions: sessions)
            importStatus = String(format: L("imported_n"), n)
        }
        .alert(L("import_title"), isPresented: Binding(
            get: { importStatus != nil },
            set: { if !$0 { importStatus = nil } }
        )) {
            Button(L("ok")) { importStatus = nil }
        } message: {
            Text(importStatus ?? "")
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.item]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  data.count <= 100 * 1024 * 1024 else { return }  // 单文件 100MB 上限，不显示、内部执行
            pendingFileName = url.lastPathComponent
            pendingFileText = String(data: data, encoding: .utf8).map { String($0.prefix(20000)) }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    pendingImage = Self.compressedJPEG(data)
                }
                photoItem = nil
            }
        }
    }

    // MARK: 建议 chips（横向滚动，第一个黑底白字带下载图标）

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { idx, s in
                    Button {
                        if idx == 0 { showingImport = true }
                        else { draft = s; focused = true }
                    } label: {
                        HStack(spacing: 5) {
                            if idx == 0 {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            Text(s).font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(idx == 0 ? Palette.ink : Palette.field, in: Capsule())
                        .foregroundStyle(idx == 0 ? Palette.onInk : Palette.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: 顶栏（返回 chevron 白圆 + 居中模型 pill）

    private var topBar: some View {
        ZStack {
            HStack {
                Button(action: onOpenSessions) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 40, height: 40)
                        .background(Palette.background, in: Circle())
                        .overlay(Circle().stroke(Palette.stroke, lineWidth: 1))
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("session_list"))
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            Button { openModelSheet() } label: {
                HStack(spacing: 6) {
                    Text(modelName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Palette.secondary)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .barTitleGlass()
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("model_label") + "：\(modelName)")
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private func openModelSheet() {
        if directAgent == nil { _ = store.ensureDirectChat() }
        showingModelSheet = true
    }

    private func setMode(_ effort: String) {
        let agentId: UUID
        if let a = directAgent {
            agentId = a.id
        } else {
            let convId = store.ensureDirectChat()
            guard let first = store.conversations
                .first(where: { $0.id == convId })?.memberIds.first else { return }
            agentId = first
        }
        store.setAgentEffort(agentId: agentId, effort: effort)
    }

    // MARK: 输入框（白底 r28 玻璃：+ 在左，发送在右）

    private var composer: some View {
        VStack(spacing: 8) {
            if pendingImage != nil || pendingFileName != nil {
                HStack(spacing: 8) {
                    if let data = pendingImage, let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable().scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    if let name = pendingFileName {
                        Label(name, systemImage: "doc.fill")
                            .font(.caption).lineLimit(1)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Palette.control, in: Capsule())
                    }
                    Button {
                        pendingImage = nil; pendingFileName = nil; pendingFileText = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 6)
            }
            HStack(alignment: .bottom, spacing: 6) {
                Menu {
                    if store.agentSupportsVision(directAgent) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(L("send_image"), systemImage: "photo")
                        }
                    }
                    Button { showingFileImporter = true } label: {
                        Label(L("send_file"), systemImage: "doc")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 38, height: 38)
                        .background(Palette.control, in: Circle())
                        .frame(minWidth: 44, minHeight: 44)
                }
                TextField(L("send_message"), text: $draft, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...5)
                    .focused($focused)
                    .padding(.vertical, 11)
                // 语音圆（原版 home.png：右端灰圆 + 声波图标）：识别器不可用或权限被拒时不画。
                if dictation.canDictate {
                    Button(action: toggleDictation) {
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(dictation.isRecording ? Palette.onInk : Palette.ink)
                            .frame(width: 38, height: 38)
                            .background(dictation.isRecording ? Color.red : Palette.control, in: Circle())
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dictation.isRecording ? L("stop_dictation") : L("voice_input"))
                }
                if canSend {
                    Button(action: sendDraft) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Palette.onInk)
                            .frame(width: 38, height: 38)
                            .background(Palette.ink, in: Circle())
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("send_message"))
                }
            }
        }
        .padding(5)
        .composerSurface()
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }

    private func toggleDictation() {
        if dictation.isRecording {
            dictation.stop()
        } else {
            dictationBase = draft
            dictation.start()
        }
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        if dictation.isRecording { dictation.stop() }
        draft = ""
        let convId = store.ensureDirectChat()
        let dest = ChatDestination(id: convId, firstMessage: text,
                                   image: pendingImage,
                                   fileName: pendingFileName,
                                   fileText: pendingFileText)
        pendingImage = nil; pendingFileName = nil; pendingFileText = nil
        onOpenConversation(dest)
    }

    /// 图片压到最长边 1280 的 JPEG（跟聊天页同一条规矩）。
    private static func compressedJPEG(_ data: Data) -> Data? {
        guard let ui = UIImage(data: data) else { return data }
        let maxSide: CGFloat = 1280
        let scale = min(1, maxSide / max(ui.size.width, ui.size.height))
        let size = CGSize(width: ui.size.width * scale, height: ui.size.height * scale)
        let rendered = UIGraphicsImageRenderer(size: size).image { _ in
            ui.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.jpegData(compressionQuality: 0.8)
    }
}
