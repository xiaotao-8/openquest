import SwiftUI

/// Discover (§1.4): the Agent work desktop card on top, segments
/// Feed / Ideas / Goals / Spaces / Library, each with its empty state in
/// Phase 1. Created goals/spaces persist locally; their content is Phase 2.
struct DiscoverView: View {
    @EnvironmentObject private var store: AppStore
    @State private var segment = 0
    @State private var showingDesktop = false
    @State private var showingFeedPrompt = false
    @State private var showingNewGoal = false
    @State private var showingNewSpace = false
    @State private var showingResearch = false
    @State private var selectedGoal: GoalItem?
    @State private var selectedSpace: SpaceItem?

    private var segments: [String] {
        [L("简报"), L("建议"), L("目标"), L("小工具"), L("内容库")]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ScreenHeader(title: L("发现"))
                desktopCard
                researchCard
                TabChoice(titles: segments, selection: $segment)
                    .padding(.horizontal, 20)
                segmentContent
            }
            .padding(.bottom, 24)
        }
        .background(Palette.background)
        .codyncSheet(isPresented: $showingDesktop) {
            AgentDesktopView()
        }
        .codyncSheet(isPresented: $showingFeedPrompt) {
            FeedPromptEditor()
        }
        .codyncSheet(isPresented: $showingNewGoal) {
            NewGoalView()
        }
        .codyncSheet(isPresented: $showingNewSpace) {
            NewSpaceView()
        }
        .codyncSheet(isPresented: $showingResearch) {
            DeepResearchView()
        }
        .codyncSheet(isPresented: Binding(get: { selectedGoal != nil }, set: { if !$0 { selectedGoal = nil } })) {
            if let goal = selectedGoal {
                NavigationStack { GoalDetailView(goal: goal) }
            }
        }
        .codyncSheet(isPresented: Binding(get: { selectedSpace != nil }, set: { if !$0 { selectedSpace = nil } })) {
            if let space = selectedSpace {
                NavigationStack { SpaceDetailView(space: space) }
            }
        }
    }

    private var desktopCard: some View {
        Button {
            showingDesktop = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 24))
                    .foregroundStyle(Palette.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("工作桌面"))
                        .font(.headline)
                        .foregroundStyle(Palette.text)
                    Text(L("看智能体在电脑上干活：终端、文件、浏览器、任务进度。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.tertiary)
            }
            .padding(16)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    private var researchCard: some View {
        Button {
            showingResearch = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24))
                    .foregroundStyle(Palette.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("深度研究"))
                        .font(.headline)
                        .foregroundStyle(Palette.text)
                    Text(L("让智能体查资料、对比来源，给你一份结构化报告。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.tertiary)
            }
            .padding(16)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    /// The saved briefing prompt, or the default one when empty.
    private var feedPromptText: String {
        let saved = UserDefaults.standard.string(forKey: "cn.lingyu.feedPrompt") ?? ""
        return saved.isEmpty ? L("请写一期简报：从最近的对话里整理出今天值得看的内容。") : saved
    }

    @ViewBuilder
    private var segmentContent: some View {
        switch segment {
        case 0:
            FeedSectionView(onEditPrompt: { showingFeedPrompt = true }, onGenerate: {
                store.draftToLeadBot(feedPromptText)
            })
        case 1:
            IdeasSectionView()
        case 2:
            GoalsSectionView(onCreate: { showingNewGoal = true }, onSelect: { selectedGoal = $0 })
        case 3:
            SpacesSectionView(onCreate: { showingNewSpace = true }, onSelect: { selectedSpace = $0 })
        default:
            LibrarySectionView()
        }
    }
}

struct EmptyState: View {
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?
    /// When false the action shows disabled (§1.6.4) with `disabledNote`.
    var actionEnabled = true
    var disabledNote: String?

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Palette.text)
            Text(message)
                .font(.body)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.primary)
                    .disabled(!actionEnabled)
                    .opacity(actionEnabled ? 1 : 0.4)
                if !actionEnabled, let disabledNote {
                    Text(disabledNote)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 40)
    }
}

/// Feed: posts the user saved from chat (or drafted from a routine).
/// The first post is drafted to the lead agent in chat — the agent writes
/// it, and the user saves it from the chat bubble into the Feed.
struct FeedSectionView: View {
    var onEditPrompt: () -> Void
    var onGenerate: () -> Void
    @EnvironmentObject private var store: AppStore
    @State private var expandedId: UUID?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    onEditPrompt()
                } label: {
                    Label(L("简报提示"), systemImage: "text.quote")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.secondary)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 20)
            if store.feed.posts.isEmpty {
                EmptyState(
                    title: L("还没有简报"),
                    message: L("按简报提示让智能体在聊天里写一期，写好后从聊天里保存到简报。"),
                    actionTitle: L("生成第一期"),
                    action: onGenerate,
                    actionEnabled: store.leadBot != nil,
                    disabledNote: L("需要先配对电脑并有智能体。")
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(store.feed.posts) { post in
                        FeedPostRow(post: post, expanded: expandedId == post.id, onToggle: {
                            expandedId = expandedId == post.id ? nil : post.id
                        })
                    }
                }
            }
        }
    }
}

private struct FeedPostRow: View {
    var post: FeedPost
    var expanded: Bool
    var onToggle: () -> Void
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                onToggle()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(post.category)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                        Spacer()
                        Text(DateFormatter.auditTime.string(from: post.createdAt))
                            .font(.caption)
                            .foregroundStyle(Palette.tertiary)
                    }
                    Text(post.title)
                        .font(.headline)
                        .foregroundStyle(Palette.text)
                        .multilineTextAlignment(.leading)
                    Text(post.body)
                        .font(.body)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(expanded ? nil : 3)
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)
            HStack(spacing: 16) {
                Button {
                    store.feed.setFeedback(id: post.id, feedback: post.feedback == .up ? .none : .up)
                } label: {
                    Image(systemName: post.feedback == .up ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .foregroundStyle(post.feedback == .up ? Palette.accent : Palette.secondary)
                }
                Button {
                    store.feed.setFeedback(id: post.id, feedback: post.feedback == .down ? .none : .down)
                } label: {
                    Image(systemName: post.feedback == .down ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .foregroundStyle(post.feedback == .down ? Palette.accent : Palette.secondary)
                }
                Button {
                    store.draftToLeadBot(L("聊聊这个话题：%@。", post.title))
                } label: {
                    Text(L("聊聊"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.accent)
                }
                .disabled(store.leadBot == nil)
                .opacity(store.leadBot == nil ? 0.4 : 1)
                Spacer()
            }
            .font(.subheadline)
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

/// Ideas: suggestions the user saved from chat (or typed in directly).
struct IdeasSectionView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        if store.ideas.ideas.isEmpty {
            EmptyState(
                title: L("还没有建议"),
                message: L("在聊天里看到好主意时，长按消息选「保存为建议」，它会出现在这里。"),
                actionTitle: nil,
                action: nil
            )
        } else {
            VStack(spacing: 0) {
                ForEach(store.ideas.ideas) { idea in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(idea.title)
                                .font(.body)
                                .foregroundStyle(Palette.text)
                            Text(idea.category)
                                .font(.caption)
                                .foregroundStyle(Palette.secondary)
                        }
                        Spacer()
                        Button {
                            store.draftToLeadBot(L("聊聊这个想法：%@。", idea.title))
                        } label: {
                            Text(L("聊聊"))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Palette.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(store.leadBot == nil)
                        .opacity(store.leadBot == nil ? 0.4 : 1)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
        }
    }
}

/// Goals: the user's goals with progress entries and a done state.
/// Categories are the Muse seven; older category values migrate on load.
struct GoalsSectionView: View {
    var onCreate: () -> Void
    var onSelect: (GoalItem) -> Void
    @EnvironmentObject private var store: AppStore

    var body: some View {
        if store.goals.goals.isEmpty {
            EmptyState(
                title: L("还没有目标"),
                message: L("定一个目标，智能体会帮你拆解、跟进进度。"),
                actionTitle: L("新建目标"),
                action: onCreate
            )
        } else {
            VStack(spacing: 0) {
                ForEach(store.goals.goals) { goal in
                    Button {
                        onSelect(goal)
                    } label: {
                        HStack {
                            Image(systemName: goal.completed ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(goal.completed ? .green : Palette.tertiary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(goal.title)
                                    .font(.body)
                                    .foregroundStyle(Palette.text)
                                    .strikethrough(goal.completed)
                                Text("\(GoalCategory(rawValue: goal.type)?.label ?? goal.type) · \(L("%d 条进展", goal.progress.count))")
                                    .font(.caption)
                                    .foregroundStyle(Palette.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Palette.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
        }
    }
}

/// Goal detail: progress entries, add progress, mark done, delete.
struct GoalDetailView: View {
    var goal: GoalItem
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var progressText = ""

    private var liveGoal: GoalItem? {
        store.goals.goals.first { $0.id == goal.id }
    }

    var body: some View {
        List {
            Section {
                if let liveGoal {
                    Text(liveGoal.title)
                        .font(.headline)
                    Text(GoalCategory(rawValue: liveGoal.type)?.label ?? liveGoal.type)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                }
            }
            Section {
                if let liveGoal, !liveGoal.progress.isEmpty {
                    ForEach(liveGoal.progress) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.text)
                                .font(.body)
                            Text(DateFormatter.auditTime.string(from: entry.date))
                                .font(.caption)
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                } else {
                    Text(L("还没有进展记录。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                }
                HStack {
                    TextField(L("记一条进展…"), text: $progressText)
                    Button(L("记下")) {
                        let text = progressText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        store.goals.addProgress(goalId: goal.id, text: text)
                        progressText = ""
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .disabled(progressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text(L("进展"))
            }
            Section {
                if let liveGoal {
                    Button {
                        store.goals.setCompleted(goalId: goal.id, completed: !liveGoal.completed)
                    } label: {
                        Text(liveGoal.completed ? L("标为未完成") : L("标为已完成"))
                    }
                    Button(role: .destructive) {
                        store.goals.remove(id: goal.id)
                        dismiss()
                    } label: {
                        Text(L("删除这个目标"))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("目标"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("关闭")) { dismiss() }
            }
        }
    }
}

/// Spaces: mini-tools the user asked an agent to build. A space starts as
/// a request and is built through chat; the list shows the request and
/// its state, never a fake working tool.
struct SpacesSectionView: View {
    var onCreate: () -> Void
    var onSelect: (SpaceItem) -> Void
    @EnvironmentObject private var store: AppStore

    var body: some View {
        if store.spaces.spaces.isEmpty {
            EmptyState(
                title: L("还没有小工具"),
                message: L("描述一个你想要的小工具，它会为你搭出来。"),
                actionTitle: L("描述一个来创建"),
                action: onCreate
            )
        } else {
            VStack(spacing: 0) {
                ForEach(store.spaces.spaces) { space in
                    Button {
                        onSelect(space)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(space.title)
                                    .font(.body)
                                    .foregroundStyle(Palette.text)
                                Text(L("待搭建"))
                                    .font(.caption)
                                    .foregroundStyle(Palette.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Palette.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
        }
    }
}

/// Space detail: the request, its state, and a way to keep building it
/// in chat. The tool itself is built by the agent; the app does not
/// pretend it is already running.
struct SpaceDetailView: View {
    var space: SpaceItem
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Text(space.title)
                    .font(.headline)
                if !space.description.isEmpty {
                    Text(space.description)
                        .font(.body)
                        .foregroundStyle(Palette.secondary)
                }
                Text(L("待搭建"))
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
            } footer: {
                Text(L("小工具由智能体在电脑端搭建，搭好后会回到聊天里告诉你。"))
            }
            Section {
                Button {
                    store.draftToLeadBot(L("继续搭建这个小工具：%@。", space.title))
                    dismiss()
                } label: {
                    Label(L("在聊天里继续搭建"), systemImage: "message")
                }
                .disabled(store.leadBot == nil)
                Button(role: .destructive) {
                    store.spaces.remove(id: space.id)
                    dismiss()
                } label: {
                    Text(L("删除这个小工具"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("小工具"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("关闭")) { dismiss() }
            }
        }
    }
}

struct FeedPromptEditor: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cn.lingyu.feedPrompt") private var prompt = ""

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("简报提示")) {
                dismiss()
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(L("简报按这条提示生成。留空时用默认提示。"))
                    .font(.body)
                    .foregroundStyle(Palette.secondary)
                TextEditor(text: $prompt)
                    .font(.body)
                    .frame(minHeight: 160)
                    .padding(12)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                Spacer()
                PrimaryActionButton(title: L("保存")) {
                    dismiss()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Palette.background)
    }
}

struct NewGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var title = ""
    @State private var type = GoalCategory.health.rawValue

    private var types: [(value: String, title: String)] {
        GoalCategory.allCases.map { (value: $0.rawValue, title: $0.label) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("新建目标")) {
                dismiss()
            }
            VStack(spacing: 20) {
                TextField(L("目标是什么"), text: $title)
                    .font(.title3)
                    .padding(14)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                SegmentedChoice(options: types, selection: $type)
                Spacer()
                PrimaryActionButton(title: L("创建目标"), isEnabled: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    store.goals.add(title: title.trimmingCharacters(in: .whitespacesAndNewlines), type: type)
                    dismiss()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Palette.background)
    }
}

struct NewSpaceView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var description = ""

    private var examples: [String] {
        [L("倒数日"), L("番茄钟"), L("记账本")]
    }

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("新建小工具")) {
                dismiss()
            }
            VStack(spacing: 20) {
                TextField(L("描述你想要的小工具…"), text: $description, axis: .vertical)
                    .font(.body)
                    .lineLimit(3...6)
                    .padding(14)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                HStack(spacing: 8) {
                    ForEach(examples, id: \.self) { example in
                        Button(example) {
                            description = example
                        }
                        .buttonStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
                PrimaryActionButton(title: L("创建"), isEnabled: !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.spaces.add(title: text, description: "")
                    store.draftToLeadBot(L("请帮我搭建一个小工具：%@。", text))
                    dismiss()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Palette.background)
    }
}

/// Library: artifacts the agents wrote and files shared in chat, read
/// from the real event mirror — plus the app's own files on this device.
/// An artifact row opens the chat it came from; there is no artifact
/// viewer yet, and the app does not pretend otherwise.
struct LibrarySectionView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingSystemFiles = false

    private var artifacts: [(entry: Entry, bot: Bot)] {
        store.connector.mirror.bots.flatMap { bot in
            store.connector.mirror.entries(for: bot.id)
                .filter { $0.kind == "artifact" }
                .map { (entry: $0, bot: bot) }
        }
        .sorted { $0.entry.createdAt > $1.entry.createdAt }
    }

    private var media: [(attachment: EntryAttachment, bot: Bot, date: Int64)] {
        let imageSuffixes = ["jpg", "jpeg", "png", "gif", "webp", "heic"]
        return store.connector.mirror.bots.flatMap { bot in
            store.connector.mirror.entries(for: bot.id).flatMap { entry in
                (entry.data.attachments ?? []).filter { attachment in
                    imageSuffixes.contains { attachment.name.lowercased().hasSuffix(".\($0)") }
                }.map { (attachment: $0, bot: bot, date: entry.createdAt) }
            }
        }
        .sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                showingSystemFiles = true
            } label: {
                HStack {
                    Label(L("系统文件"), systemImage: "folder")
                        .font(.body)
                        .foregroundStyle(Palette.text)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.tertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            if artifacts.isEmpty && media.isEmpty {
                EmptyState(
                    title: L("内容库是空的"),
                    message: L("去聊天里让智能体写一个 artifact，它会出现在这里。"),
                    actionTitle: L("去聊天"),
                    action: { store.selectedTab = 0 }
                )
            } else {
                if !artifacts.isEmpty {
                    libraryHeader(L("Artifacts"))
                    ForEach(artifacts, id: \.entry.id) { item in
                        Button {
                            store.openChat(botId: item.bot.id)
                        } label: {
                            libraryRow(
                                title: item.entry.data.title ?? L("未命名"),
                                detail: item.bot.name,
                                date: item.entry.createdAt
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !media.isEmpty {
                    libraryHeader(L("媒体"))
                    ForEach(media, id: \.attachment.id) { item in
                        Button {
                            store.openChat(botId: item.bot.id)
                        } label: {
                            libraryRow(
                                title: item.attachment.name,
                                detail: item.bot.name,
                                date: item.date
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .codyncSheet(isPresented: $showingSystemFiles) {
            SystemFilesView()
        }
    }

    private func libraryHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    private func libraryRow(title: String, detail: String, date: Int64) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Palette.text)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Palette.secondary)
            }
            Spacer()
            Text(DateFormatter.auditTime.string(from: Date(timeIntervalSince1970: TimeInterval(date) / 1000)))
                .font(.caption)
                .foregroundStyle(Palette.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

/// The app's own files on this device (Documents/): identity files,
/// avatars, and anything else the app stored. Read-only list.
struct SystemFilesView: View {
    @Environment(\.dismiss) private var dismiss

    private var files: [(name: String, size: Int)] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: docs, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else { return [] }
        return items.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            let isDir = values?.isDirectory == true
            return (name: url.lastPathComponent + (isDir ? "/" : ""), size: values?.fileSize ?? 0)
        }.sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("系统文件")) {
                dismiss()
            }
            if files.isEmpty {
                EmptyState(
                    title: L("没有文件"),
                    message: L("本机还没有存任何文件。"),
                    actionTitle: nil,
                    action: nil
                )
            } else {
                List {
                    ForEach(files, id: \.name) { file in
                        HStack {
                            Text(file.name)
                                .font(.body)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(Palette.background)
    }
}

/// The agent work desktop (§N): terminal / files / browser / task progress
/// in one desktop view — watching the agent work on the cloud computer.
/// Not a remote screen. Phase 1 is the shell; live panels are Phase 2.
struct AgentDesktopView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    private var workingBots: [Bot] {
        store.connector.mirror.bots.filter { $0.isWorking }
    }

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("工作桌面")) {
                dismiss()
            }
            ScrollView {
                VStack(spacing: 16) {
                    if workingBots.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 44, weight: .ultraLight))
                                .foregroundStyle(Palette.tertiary)
                            Text(L("现在没有智能体在干活"))
                                .font(.headline)
                                .foregroundStyle(Palette.text)
                            Text(L("智能体开始工作后，这里会实时显示它的终端、文件、浏览器和任务进度。"))
                                .font(.body)
                                .foregroundStyle(Palette.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        ForEach(workingBots) { bot in
                            DesktopBotCard(bot: bot)
                        }
                        Text(L("终端、文件、浏览器面板需要电脑端提供实时画面接口，尚未接通。任务进度是实时的。"))
                            .font(.footnote)
                            .foregroundStyle(Palette.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(Palette.background)
    }
}

struct DesktopBotCard: View {
    var bot: Bot
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AvatarView(bot: bot, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bot.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.text)
                    Text(bot.activity.isEmpty ? L("工作中…") : bot.activity)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(L("去看看")) {
                    store.openChat(botId: bot.id)
                }
                .buttonStyle(.secondary)
            }
            HStack(spacing: 8) {
                DesktopPanelTile(icon: "terminal", title: L("终端"), detail: L("未接入"), disabled: true)
                DesktopPanelTile(icon: "folder", title: L("文件"), detail: L("未接入"), disabled: true)
                DesktopPanelTile(icon: "globe", title: L("浏览器"), detail: L("未接入"), disabled: true)
                DesktopPanelTile(icon: "list.bullet", title: L("任务"),
                                 detail: L("%d 个进行中", bot.workSections.live.count), disabled: false)
            }
        }
        .padding(16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct DesktopPanelTile: View {
    var icon: String
    var title: String
    var detail: String?
    var disabled = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Palette.secondary)
            Text(title)
                .font(.caption)
                .foregroundStyle(Palette.secondary)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(disabled ? Palette.tertiary : Palette.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
        .opacity(disabled ? 0.6 : 1)
    }
}
