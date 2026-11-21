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

    private var segments: [String] {
        [L("简报"), L("建议"), L("目标"), L("小工具"), L("内容库")]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ScreenHeader(title: L("发现"))
                desktopCard
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

    @ViewBuilder
    private var segmentContent: some View {
        switch segment {
        case 0:
            EmptyState(
                title: L("还没有简报"),
                body: L("简报会按你的提示，从对话和已连数据里整理出每天值得看的内容。"),
                actionTitle: L("生成第一期"),
                action: { showingFeedPrompt = true }
            )
        case 1:
            EmptyState(
                title: L("还没有建议"),
                body: L("建议从对话与已连数据生成：值得做的事、值得看的内容、值得试的用法。"),
                actionTitle: nil,
                action: nil
            )
        case 2:
            GoalsEmptyState(onCreate: { showingNewGoal = true })
        case 3:
            SpacesEmptyState(onCreate: { showingNewSpace = true })
        default:
            EmptyState(
                title: L("内容库是空的"),
                body: L("去聊天里让智能体写一个 artifact，它会出现在这里。"),
                actionTitle: L("去聊天"),
                action: { store.selectedTab = 0 }
            )
        }
    }
}

struct EmptyState: View {
    var title: String
    var body: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Palette.text)
            Text(body)
                .font(.body)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 40)
    }
}

/// The user's saved goals (local list; progress tracking is Phase 2).
struct GoalItem: Codable, Identifiable {
    var id = UUID()
    var title: String
    var type: String
}

struct GoalsEmptyState: View {
    var onCreate: () -> Void
    @AppStorage("cn.lingyu.goals") private var goalsData = Data()

    private var goals: [GoalItem] {
        (try? JSONDecoder().decode([GoalItem].self, from: goalsData)) ?? []
    }

    var body: some View {
        if goals.isEmpty {
            EmptyState(
                title: L("还没有目标"),
                body: L("定一个目标，智能体会帮你拆解、跟进进度。"),
                actionTitle: L("新建目标"),
                action: onCreate
            )
        } else {
            VStack(spacing: 0) {
                ForEach(goals) { goal in
                    HStack {
                        Text(goal.title)
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Text(goal.type)
                            .font(.caption)
                            .foregroundStyle(Palette.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
        }
    }
}

struct SpacesEmptyState: View {
    var onCreate: () -> Void
    @AppStorage("cn.lingyu.spaces") private var spacesData = Data()

    private var spaces: [GoalItem] {
        (try? JSONDecoder().decode([GoalItem].self, from: spacesData)) ?? []
    }

    var body: some View {
        if spaces.isEmpty {
            EmptyState(
                title: L("还没有小工具"),
                body: L("描述一个你想要的小工具，它会为你搭出来。"),
                actionTitle: L("描述一个来创建"),
                action: onCreate
            )
        } else {
            VStack(spacing: 0) {
                ForEach(spaces) { space in
                    HStack {
                        Text(space.title)
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Text(space.type)
                            .font(.caption)
                            .foregroundStyle(Palette.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
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
    @AppStorage("cn.lingyu.goals") private var goalsData = Data()
    @State private var title = ""
    @State private var type = "habit"

    private var types: [(value: String, title: String)] {
        [
            ("habit", L("习惯")),
            ("learning", L("学习")),
            ("health", L("健康")),
            ("finance", L("财务")),
            ("project", L("项目")),
            ("travel", L("旅行")),
            ("other", L("其他")),
        ]
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
                    var goals = (try? JSONDecoder().decode([GoalItem].self, from: goalsData)) ?? []
                    goals.append(GoalItem(title: title.trimmingCharacters(in: .whitespacesAndNewlines), type: types.first { $0.value == type }?.title ?? type))
                    goalsData = (try? JSONEncoder().encode(goals)) ?? Data()
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
    @AppStorage("cn.lingyu.spaces") private var spacesData = Data()
    @State private var description = ""

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
                Spacer()
                PrimaryActionButton(title: L("创建"), isEnabled: !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    var spaces = (try? JSONDecoder().decode([GoalItem].self, from: spacesData)) ?? []
                    spaces.append(GoalItem(title: description.trimmingCharacters(in: .whitespacesAndNewlines), type: L("小工具")))
                    spacesData = (try? JSONEncoder().encode(spaces)) ?? Data()
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
                DesktopPanelTile(icon: "terminal", title: L("终端"))
                DesktopPanelTile(icon: "folder", title: L("文件"))
                DesktopPanelTile(icon: "globe", title: L("浏览器"))
                DesktopPanelTile(icon: "list.bullet", title: L("任务"))
            }
        }
        .padding(16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct DesktopPanelTile: View {
    var icon: String
    var title: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Palette.secondary)
            Text(title)
                .font(.caption)
                .foregroundStyle(Palette.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
    }
}
