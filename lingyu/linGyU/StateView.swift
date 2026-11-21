import SwiftUI

/// State (§1.1): Widget / Live Activity / Dynamic Island segments + three
/// galleries + Usage entry. The pending-approvals block stays (a fusion
/// addition): it is the ApprovalSheet's entry point.
struct StateView: View {
    @EnvironmentObject private var store: AppStore
    @State private var segment = 0
    @State private var showingUsage = false
    @State private var showingApprovals = false
    @State private var showingAllApprovals = false
    @State private var showingUpcoming = false
    @State private var showingAudit = false
    @State private var didHandlePreview = false

    private var segments: [String] {
        [L("小组件"), L("实时活动"), L("灵动岛")]
    }

    private var pendingEntries: [Entry] {
        store.connector.mirror.bots.flatMap { bot in
            store.connector.mirror.entries(for: bot.id).filter { $0.isWaitingCard }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ScreenHeader(title: L("状态"), trailing: AnyView(
                        Button {
                            showingUsage = true
                        } label: {
                            Image(systemName: "chart.bar")
                        }
                        .buttonStyle(.iconButton)
                        .accessibilityLabel(L("用量"))
                    ))
                    SegmentedChoice(options: segments.enumerated().map { (value: $0.offset, title: $0.element) }, selection: $segment)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    if !pendingEntries.isEmpty {
                        approvalsSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                    }
                    switch segment {
                    case 0:
                        NavigationStack {
                            WidgetGalleryView()
                        }
                        .environment(\.stateSurfaceActive, store.selectedTab == 2 && segment == 0)
                    case 1:
                        ActivityGalleryView(forms: [.lockScreen])
                    default:
                        ActivityGalleryView(forms: [.compact, .minimal, .expanded])
                    }
                    lowerSections
                        .id("lower")
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                }
            }
            .background(Palette.background)
            .codyncSheet(isPresented: $showingUsage) {
                UsageView()
            }
            .codyncSheet(isPresented: $showingApprovals) {
                if let bot = firstPendingBot {
                    ApprovalSheet(entries: pendingEntries, bot: bot)
                }
            }
            .codyncSheet(isPresented: $showingAllApprovals) {
                NavigationStack { ApprovalsView() }
            }
            .codyncSheet(isPresented: $showingUpcoming) {
                NavigationStack { UpcomingView() }
            }
            .codyncSheet(isPresented: $showingAudit) {
                NavigationStack { AuditLogView() }
            }
            .onAppear {
                if !didHandlePreview, case .seeded(let options) = store.previewMode {
                    didHandlePreview = true
                    if options.audit { showingAudit = true }
                    if options.stateLower {
                        // Let the layout settle, then jump to the new sections.
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            proxy.scrollTo("lower", anchor: .top)
                        }
                    }
                }
            }
        }
    }

    /// Activity / Approvals / Upcoming / 审核记录, below the galleries.
    private var lowerSections: some View {
        VStack(spacing: 16) {
            ActivitySectionView()
            CardSection(title: L("审批")) {
                CardRow {
                    Button {
                        showingAllApprovals = true
                    } label: {
                        HStack {
                            Text(approvalSummary)
                                .foregroundStyle(Palette.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Palette.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            CardSection(title: L("即将到来")) {
                CardRow {
                    Button {
                        showingUpcoming = true
                    } label: {
                        HStack {
                            Text(L("还没有定时任务"))
                                .foregroundStyle(Palette.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Palette.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            CardSection(title: L("审核记录")) {
                CardRow {
                    Button {
                        showingAudit = true
                    } label: {
                        HStack {
                            Text(auditSummary)
                                .foregroundStyle(Palette.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Palette.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var approvalSummary: String {
        let decided = store.audit.records.filter { $0.kind == .approval }.count
        if pendingEntries.isEmpty {
            return decided == 0 ? L("没有待审批的请求") : L("%d 个已决定", decided)
        }
        return L("%d 个待决 · %d 个已决定", pendingEntries.count, decided)
    }

    private var auditSummary: String {
        let today = store.audit.records.filter { Calendar.current.isDateInToday($0.date) }.count
        if store.audit.records.isEmpty {
            return L("还没有记录")
        }
        return L("共 %d 条 · 今天 %d 条", store.audit.records.count, today)
    }

    private var firstPendingBot: Bot? {
        guard let entry = pendingEntries.first else { return nil }
        return store.connector.mirror.bot(id: entry.botId)
    }

    private var approvalsSection: some View {
        CardSection(title: L("待审批")) {
            CardRow {
                Button {
                    showingApprovals = true
                } label: {
                    HStack {
                        Text(L("%d 个请求等你确认", pendingEntries.count))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The Usage sheet: per-provider cards. The `usage` RPC is a Phase 2 item,
/// so the sheet shows an honest empty state — never a number.
struct UsageView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: L("用量"), trailing: AnyView(
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.iconButton)
                .accessibilityLabel(L("关闭"))
            ))
            if !store.connector.isPaired {
                VStack(spacing: 14) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundStyle(Palette.tertiary)
                    Text(L("还没有连接电脑"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.text)
                    Text(L("连接电脑后，这里会显示用量。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                VStack(spacing: 12) {
                    Text(L("还没有用量数据"))
                        .font(.headline)
                        .foregroundStyle(Palette.text)
                    Text(L("连接电脑后，这里会按供应商显示用量与剩余额度。"))
                        .font(.body)
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
                Spacer()
            }
        }
        .background(Palette.background)
    }
}

/// Activity: what the agents are doing right now (live mirror) and the
/// most recently finished work. Empty when nothing is working.
struct ActivitySectionView: View {
    @EnvironmentObject private var store: AppStore

    private var workingBots: [Bot] {
        store.connector.mirror.workingBots
    }

    private var recentTasks: [(task: WorkTask, botName: String)] {
        let all = store.connector.mirror.bots.flatMap { bot in
            bot.workSections.recent.map { (task: $0, botName: bot.name) }
        }
        return Array(all.sorted { $0.task.createdAt > $1.task.createdAt }.prefix(5))
    }

    var body: some View {
        CardSection(title: L("活动")) {
            if workingBots.isEmpty && recentTasks.isEmpty {
                CardRow {
                    Text(L("暂无活动"))
                        .foregroundStyle(Palette.secondary)
                }
            } else {
                ForEach(workingBots) { bot in
                    CardRow {
                        Button {
                            store.openChat(botId: bot.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bot.name)
                                        .font(.body)
                                        .foregroundStyle(Palette.text)
                                    Text(bot.workSections.live.first?.title ?? bot.activity)
                                        .font(.caption)
                                        .foregroundStyle(Palette.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(L("进行中"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                ForEach(recentTasks, id: \.task.id) { item in
                    CardRow {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.task.title)
                                    .font(.body)
                                    .foregroundStyle(Palette.text)
                                    .lineLimit(1)
                                Text(item.botName)
                                    .font(.caption)
                                    .foregroundStyle(Palette.secondary)
                            }
                            Spacer()
                            Text(L("已完成"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                }
            }
        }
    }
}
