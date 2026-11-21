import SwiftUI
import PhotosUI

/// The bot detail sheet (§6): identity header + five tabs
/// (Details / Computer / Library / Memory / Settings). Settings autosave
/// 600 ms after the last change.
struct BotDetailsView: View {
    var bot: Bot
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var draft: BotDraft
    @State private var saveTask: Task<Void, Never>?
    @State private var saveError: String?
    @State private var showingDeleteDialog = false

    private var tabs: [String] {
        [L("详情"), L("电脑"), L("资料库"), L("记忆"), L("设置")]
    }

    init(bot: Bot) {
        self.bot = bot
        _draft = State(initialValue: BotDraft.from(bot: bot))
    }

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: bot.name) {
                dismiss()
            }
            ScrollView {
                VStack(spacing: 0) {
                    identityHeader
                    TabChoice(titles: tabs, selection: $tab)
                        .padding(.top, 18)
                    VStack(spacing: 20) {
                        switch tab {
                        case 0: DetailsTab(bot: bot)
                        case 1: ComputerTab(bot: bot, draft: $draft, onChange: scheduleSave)
                        case 2: LibraryTab(bot: bot)
                        case 3: MemoryTab(bot: bot)
                        default: SettingsTab(bot: bot, draft: $draft, onChange: scheduleSave, onDelete: { showingDeleteDialog = true })
                        }
                    }
                    .padding(.top, 20)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    if let saveError {
                        Text(saveError)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                    }
                }
            }
        }
        .background(Palette.background)
        .codyncDialog(
            isPresented: $showingDeleteDialog,
            title: L("删除 %@？", bot.name),
            message: L("这个智能体和它的聊天记录都会被删除，且无法恢复。"),
            actions: [
                CodyncDialogAction(title: L("取消")) {},
                CodyncDialogAction(title: L("删除"), isDestructive: true) {
                    deleteBot()
                },
            ]
        )
    }

    private var identityHeader: some View {
        VStack(spacing: 10) {
            BotAvatar(bot: bot, members: bot.members.compactMap { store.connector.mirror.bot(id: $0) }, size: 72)
            Text(bot.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.text)
            HStack(spacing: 5) {
                Image(systemName: "cpu")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondary)
                Text(bot.model.map { "\(bot.backend) · \($0)" } ?? bot.backend)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .padding(.top, 8)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await save()
        }
    }

    private func save() async {
        guard let api = store.connector.api else { return }
        do {
            var draft = draft
            draft.id = bot.id
            _ = try await api.updateBot(draft: draft)
            await MainActor.run { saveError = nil }
        } catch {
            await MainActor.run {
                saveError = L("保存失败，请重试。")
            }
        }
    }

    private func deleteBot() {
        Task {
            try? await store.connector.api?.deleteBot(botId: bot.id)
            await MainActor.run {
                dismiss()
                store.navigationPath = NavigationPath()
            }
        }
    }
}

// MARK: - Details tab

struct DetailsTab: View {
    var bot: Bot
    @EnvironmentObject private var store: AppStore

    private var liveWork: [WorkTask] {
        bot.work.filter { $0.isLive }
    }

    private var waitingEntries: [Entry] {
        store.connector.mirror.entries(for: bot.id).filter { $0.isWaitingCard }
    }

    var body: some View {
        VStack(spacing: 24) {
            CardSection(title: L("线程")) {
                if liveWork.isEmpty && bot.work.isEmpty {
                    CardRow {
                        Text(L("没有正在运行的线程。"))
                            .foregroundStyle(Palette.secondary)
                    }
                } else {
                    ForEach(bot.work) { task in
                        CardRow {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .font(.body)
                                        .foregroundStyle(Palette.text)
                                    Text(workStatusText(task.status))
                                        .font(.caption)
                                        .foregroundStyle(Palette.secondary)
                                }
                                Spacer()
                                if task.isLive {
                                    Circle()
                                        .fill(Palette.secondary)
                                        .frame(width: 10, height: 10)
                                }
                            }
                        }
                        if task.id != bot.work.last?.id {
                            Hairline()
                        }
                    }
                }
            }
            if !waitingEntries.isEmpty {
                CardSection(title: L("等你处理")) {
                    ForEach(waitingEntries) { entry in
                        CardRow {
                            Button {
                                store.detailBotId = nil
                                store.openChat(botId: bot.id)
                            } label: {
                                HStack {
                                    Text(entry.data.title ?? entry.data.question ?? L("审批"))
                                        .font(.body)
                                        .foregroundStyle(Palette.text)
                                    Spacer()
                                    Circle()
                                        .fill(Palette.warning)
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        if entry.id != waitingEntries.last?.id {
                            Hairline()
                        }
                    }
                }
            }
            CardSection(title: L("定时任务")) {
                CardRow {
                    Text(L("还没有定时任务。"))
                        .foregroundStyle(Palette.secondary)
                }
            }
            CardSection(title: L("稍后")) {
                CardRow {
                    Text(L("还没有稍后提醒。"))
                        .foregroundStyle(Palette.secondary)
                }
            }
        }
    }

    private func workStatusText(_ status: String) -> String {
        switch status {
        case "waiting": return L("等待中")
        case "working": return L("进行中")
        case "needsYou": return L("需要你")
        case "done": return L("已完成")
        case "failed": return L("失败")
        case "stopped": return L("已停止")
        default: return status
        }
    }
}

// MARK: - Computer tab

struct ComputerTab: View {
    var bot: Bot
    @Binding var draft: BotDraft
    var onChange: () -> Void
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 8) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.secondary)
                Text(store.connector.computer?.name ?? L("我的电脑"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Spacer()
                Text(computerStateText)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
            }
            .padding(14)
            .background(Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.border, lineWidth: 1))
            CardSection(title: L("工作区")) {
                CardRow {
                    ValueRow(label: L("工作区"), detail: workspaceDetail, value: workspaceValue)
                }
            }
        }
    }

    private var computerStateText: String {
        switch store.connector.state {
        case .ready: return L("已连接")
        case .connecting: return L("连接中…")
        case .waiting: return L("重连中…")
        default: return L("离线")
        }
    }

    private var workspaceValue: String {
        bot.managedWorkspace ? L("专属文件夹") : L("项目文件夹")
    }

    private var workspaceDetail: String {
        bot.managedWorkspace
            ? L("这个智能体有自己的文件空间；你要求时它也可以去别的文件夹工作。")
            : L("这个项目是默认起始文件夹；你要求时它也可以去别处工作。")
    }
}

// MARK: - Library tab

struct LibraryTab: View {
    var bot: Bot

    var body: some View {
        VStack(spacing: 12) {
            Text(L("资料库是空的"))
                .font(.headline)
                .foregroundStyle(Palette.text)
            Text(L("%@ 生成的产物和这场聊天里分享的文件会显示在这里。", bot.name))
                .font(.body)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

// MARK: - Memory tab

struct MemoryTab: View {
    var bot: Bot
    @State private var segment = 0

    private var segments: [String] {
        [L("共享"), L("本智能体"), L("梦境"), L("执行")]
    }

    var body: some View {
        VStack(spacing: 20) {
            TabChoice(titles: segments, selection: $segment)
            Text(L("这里还没有记忆条目。"))
                .font(.body)
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        }
    }
}

// MARK: - Settings tab

struct SettingsTab: View {
    var bot: Bot
    @Binding var draft: BotDraft
    var onChange: () -> Void
    var onDelete: () -> Void
    @EnvironmentObject private var store: AppStore
    @State private var showingAvatarPicker = false
    @State private var instructions = ""

    var body: some View {
        VStack(spacing: 24) {
            CardSection(title: L("指令")) {
                CardRow {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("常驻指令"))
                            .foregroundStyle(Palette.text)
                        Text(L("始终适用的规则。临时要求请直接在聊天里说。"))
                            .font(.caption)
                            .foregroundStyle(Palette.secondary)
                        TextField(L("例如：审 PR 时从不直接推送。"), text: $instructions, axis: .vertical)
                            .lineLimit(3...8)
                            .onChange(of: instructions) { _, _ in onChange() }
                    }
                }
            }
            CardSection(title: L("智能体")) {
                CardRow {
                    ValueRow(label: L("后端"), value: bot.backend)
                }
                Hairline()
                CardRow {
                    ValueRow(label: L("模型"), value: bot.model ?? L("默认"))
                }
                Hairline()
                CardRow {
                    Toggle(L("快速模式"), isOn: Binding(
                        get: { draft.fastMode ?? false },
                        set: { draft.fastMode = $0; onChange() }
                    ))
                    .toggleStyle(.codync)
                }
            }
            CardSection(title: L("资料")) {
                CardRow {
                    Button {
                        showingAvatarPicker = true
                    } label: {
                        HStack {
                            Text(L("头像"))
                                .foregroundStyle(Palette.text)
                            Spacer()
                            AvatarView(name: draft.name ?? bot.name, color: draft.avatarColor ?? bot.avatarColor, shape: draft.avatarShape ?? bot.avatarShape, size: 28, ownerId: bot.id)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Hairline()
                CardRow {
                    HStack {
                        Text(L("名字"))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        TextField(L("名字"), text: Binding(
                            get: { draft.name ?? bot.name },
                            set: { draft.name = $0; onChange() }
                        ))
                        .multilineTextAlignment(.trailing)
                    }
                }
                if let createdBy = bot.createdBy {
                    Hairline()
                    CardRow {
                        ValueRow(label: L("创建者"), value: createdBy)
                    }
                }
            }
            CardSection(title: L("工作区")) {
                CardRow {
                    ValueRow(label: L("电脑"), value: store.connector.computer?.name ?? "")
                }
                Hairline()
                CardRow {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("审批"))
                            .foregroundStyle(Palette.text)
                        SegmentedChoice(
                            options: [
                                (value: "ask", title: L("每次问")),
                                (value: "auto", title: L("自动允许")),
                            ],
                            selection: Binding(
                                get: { draft.permission ?? bot.permission },
                                set: { draft.permission = $0; onChange() }
                            )
                        )
                    }
                }
                Hairline()
                CardRow {
                    Stepper(
                        L("同时线程数：%d", draft.maxThreads ?? bot.maxThreads ?? 3),
                        value: Binding(
                            get: { draft.maxThreads ?? bot.maxThreads ?? 3 },
                            set: { draft.maxThreads = $0; onChange() }
                        ),
                        in: 1...6
                    )
                }
            }
            CardSection(title: L("通知")) {
                CardRow {
                    Toggle(L("完成后通知我"), isOn: Binding(
                        get: { draft.notify ?? bot.notify ?? true },
                        set: { draft.notify = $0; onChange() }
                    ))
                    .toggleStyle(.codync)
                }
            }
            CardSection(title: L("连接器")) {
                CardRow {
                    Text(L("还没有连接器。去扩展里添加。"))
                        .foregroundStyle(Palette.secondary)
                }
            }
            CardSection(title: L("技能")) {
                CardRow {
                    Text(L("还没有技能。去扩展里获取，或自己写一个。"))
                        .foregroundStyle(Palette.secondary)
                }
            }
            Button(L("删除 %@ ", bot.name), role: .destructive) {
                onDelete()
            }
            .foregroundStyle(Palette.danger)
            .frame(maxWidth: .infinity)
        }
        .codyncSheet(isPresented: $showingAvatarPicker) {
            AvatarPicker(
                name: draft.name ?? bot.name,
                ownerId: bot.id,
                color: Binding(
                    get: { draft.avatarColor ?? bot.avatarColor },
                    set: { draft.avatarColor = $0; onChange() }
                ),
                shape: Binding(
                    get: { draft.avatarShape ?? bot.avatarShape },
                    set: { draft.avatarShape = $0; onChange() }
                )
            )
        }
    }
}

/// Avatar picker: tap the avatar to pick a photo, or keep the letter disc
/// and choose from 11 colours × 8 shapes. A photo, once set, is shown
/// everywhere the avatar appears; removing it restores the letter disc.
struct AvatarPicker: View {
    var name: String
    var ownerId: String
    @Binding var color: String
    @Binding var shape: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var avatarStore = AvatarStore.shared
    @State private var showingPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("头像")) {
                dismiss()
            }
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 10) {
                        Button {
                            showingPhotoPicker = true
                        } label: {
                            AvatarView(name: name, color: color, shape: shape, size: 72, ownerId: ownerId)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("选择照片"))
                        if avatarStore.hasPhoto(for: ownerId) {
                            Button(L("移除照片"), role: .destructive) {
                                avatarStore.remove(for: ownerId)
                            }
                            .font(.subheadline)
                            .foregroundStyle(Palette.danger)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("颜色"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.text)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                            ForEach(Palette.avatarColors, id: \.name) { item in
                                Button {
                                    color = item.name
                                } label: {
                                    Circle()
                                        .fill(item.color)
                                        .frame(width: 36, height: 36)
                                        .overlay {
                                            if color == item.name {
                                                Circle()
                                                    .stroke(Palette.text, lineWidth: 2)
                                                    .frame(width: 44, height: 44)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("形状"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.text)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                            ForEach(AvatarShape.allCases, id: \.rawValue) { item in
                                Button {
                                    shape = item.rawValue
                                } label: {
                                    ZStack {
                                        item.path(in: CGRect(x: 0, y: 0, width: 44, height: 44))
                                            .fill(Palette.avatarColor(named: color))
                                        if shape == item.rawValue {
                                            item.path(in: CGRect(x: 0, y: 0, width: 52, height: 52))
                                                .stroke(Palette.text, lineWidth: 2)
                                        }
                                    }
                                    .frame(width: 52, height: 52)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(Palette.background)
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let image = await AvatarStore.load(item) {
                    avatarStore.save(image, for: ownerId)
                }
            }
        }
    }
}

// MARK: - New bot / group

struct NewBotView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color = "blue"
    @State private var shape = "blob"
    @State private var backend = "opencode"
    @State private var permission = "ask"
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var pendingPhoto: UIImage?
    @State private var showingPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("新建智能体")) {
                dismiss()
            }
            ScrollView {
                VStack(spacing: 24) {
                    Button {
                        showingPhotoPicker = true
                    } label: {
                        AvatarView(name: name.isEmpty ? "?" : name, color: color, shape: shape, size: 72, ownerId: nil, photoOverride: pendingPhoto)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("选择照片"))
                    TextField(L("名字"), text: $name)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    AvatarPickerGrid(color: $color, shape: $shape, name: name.isEmpty ? "?" : name)
                    CardSection(title: L("智能体")) {
                        CardRow {
                            HStack {
                                Text(L("后端"))
                                    .foregroundStyle(Palette.text)
                                Spacer()
                                Menu {
                                    ForEach(["opencode", "claude", "codex", "custom"], id: \.self) { item in
                                        Button(item) { backend = item }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(backend)
                                            .foregroundStyle(Palette.secondary)
                                        Image(systemName: "chevron.down")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(Palette.secondary)
                                    }
                                }
                            }
                        }
                        Hairline()
                        CardRow {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L("审批"))
                                    .foregroundStyle(Palette.text)
                                SegmentedChoice(
                                    options: [
                                        (value: "ask", title: L("每次问")),
                                        (value: "auto", title: L("自动允许")),
                                    ],
                                    selection: $permission
                                )
                            }
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.body)
                            .foregroundStyle(Palette.danger)
                    }
                    PrimaryActionButton(title: isCreating ? L("创建中…") : L("创建"), isEnabled: !isCreating && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                        create()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(Palette.background)
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                pendingPhoto = await AvatarStore.load(item)
            }
        }
    }

    private func create() {
        guard let api = store.connector.api else { return }
        isCreating = true
        var draft = BotDraft()
        draft.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.avatarColor = color
        draft.avatarShape = shape
        draft.backend = backend
        draft.cwd = ""
        draft.permission = permission
        draft.mode = "auto"
        draft.modelOptions = [:]
        Task {
            do {
                let bot = try await api.createBot(draft: draft)
                await MainActor.run {
                    if let pendingPhoto {
                        AvatarStore.shared.save(pendingPhoto, for: bot.id)
                    }
                    dismiss()
                    store.openChat(botId: bot.id)
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = L("创建失败，请重试。")
                }
            }
        }
    }
}

struct AvatarPickerGrid: View {
    @Binding var color: String
    @Binding var shape: String
    var name: String

    var body: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                ForEach(Palette.avatarColors, id: \.name) { item in
                    Button {
                        color = item.name
                    } label: {
                        Circle()
                            .fill(item.color)
                            .frame(width: 36, height: 36)
                            .overlay {
                                if color == item.name {
                                    Circle()
                                        .stroke(Palette.text, lineWidth: 2)
                                        .frame(width: 44, height: 44)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(AvatarShape.allCases, id: \.rawValue) { item in
                    Button {
                        shape = item.rawValue
                    } label: {
                        ZStack {
                            item.path(in: CGRect(x: 0, y: 0, width: 44, height: 44))
                                .fill(Palette.avatarColor(named: color))
                            if shape == item.rawValue {
                                item.path(in: CGRect(x: 0, y: 0, width: 52, height: 52))
                                    .stroke(Palette.text, lineWidth: 2)
                            }
                        }
                        .frame(width: 52, height: 52)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct NewGroupView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedMembers: Set<String> = []
    @State private var leadId: String?
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var pendingPhoto: UIImage?
    @State private var showingPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?

    private var candidates: [Bot] {
        store.connector.mirror.bots.filter { !$0.isGroup }
    }

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("新建群聊")) {
                dismiss()
            }
            ScrollView {
                VStack(spacing: 24) {
                    Button {
                        showingPhotoPicker = true
                    } label: {
                        AvatarView(name: name.isEmpty ? "?" : name, color: "blue", shape: "blob", size: 72, ownerId: nil, photoOverride: pendingPhoto)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("选择照片"))
                    TextField(L("群名"), text: $name)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    CardSection(title: L("成员（2–12 人）")) {
                        ForEach(candidates) { bot in
                            CardRow {
                                Button {
                                    if selectedMembers.contains(bot.id) {
                                        selectedMembers.remove(bot.id)
                                    } else if selectedMembers.count < 12 {
                                        selectedMembers.insert(bot.id)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        AvatarView(bot: bot, size: 36)
                                        Text(bot.name)
                                            .foregroundStyle(Palette.text)
                                        Spacer()
                                        if selectedMembers.contains(bot.id) {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(Palette.text)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            if bot.id != candidates.last?.id {
                                Hairline()
                            }
                        }
                    }
                    if selectedMembers.count >= 2 {
                        CardSection(title: L("群主（lead）")) {
                            ForEach(candidates.filter { selectedMembers.contains($0.id) }) { bot in
                                CardRow {
                                    Button {
                                        leadId = bot.id
                                    } label: {
                                        HStack(spacing: 12) {
                                            AvatarView(bot: bot, size: 36)
                                            Text(bot.name)
                                                .foregroundStyle(Palette.text)
                                            Spacer()
                                            if leadId == bot.id {
                                                Image(systemName: "checkmark")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(Palette.text)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                                if bot.id != candidates.filter({ selectedMembers.contains($0.id) }).last?.id {
                                    Hairline()
                                }
                            }
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.body)
                            .foregroundStyle(Palette.danger)
                    }
                    PrimaryActionButton(
                        title: isCreating ? L("创建中…") : L("创建群聊"),
                        isEnabled: !isCreating && selectedMembers.count >= 2 && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        create()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(Palette.background)
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                pendingPhoto = await AvatarStore.load(item)
            }
        }
    }

    private func create() {
        guard let api = store.connector.api else { return }
        isCreating = true
        var draft = BotDraft()
        draft.kind = "group"
        draft.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.members = Array(selectedMembers)
        draft.avatarColor = "blue"
        draft.avatarShape = "blob"
        Task {
            do {
                let bot = try await api.createBot(draft: draft)
                if let leadId {
                    try? await api.setLead(botId: leadId)
                }
                await MainActor.run {
                    if let pendingPhoto {
                        AvatarStore.shared.save(pendingPhoto, for: bot.id)
                    }
                    dismiss()
                    store.openChat(botId: bot.id)
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = L("创建失败，请重试。")
                }
            }
        }
    }
}
