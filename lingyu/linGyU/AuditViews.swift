import SwiftUI

// MARK: - Audit log

/// 审核记录: everything the agents did or planned, plus every approval's
/// allow / deny / pending, searchable and filterable. Live pending
/// approvals sit on top; decided records follow below.
struct AuditLogView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var statusFilter = "all"
    @State private var botFilter = "all"
    @State private var selected: AuditRecord?
    @State private var confirmClear = false

    private var pendingEntries: [Entry] {
        store.connector.mirror.bots.flatMap { bot in
            store.connector.mirror.entries(for: bot.id).filter { $0.isWaitingCard }
        }
    }

    private var filteredRecords: [AuditRecord] {
        store.audit.records.filter { record in
            if statusFilter != "all" {
                if statusFilter == "pending" { return false }
                guard record.status.rawValue == statusFilter else { return false }
            }
            if botFilter != "all" && record.botId != botFilter { return false }
            if !query.isEmpty {
                let q = query.lowercased()
                guard record.title.lowercased().contains(q)
                    || record.detail.lowercased().contains(q)
                    || record.botName.lowercased().contains(q) else { return false }
            }
            return true
        }
    }

    private var filteredPending: [Entry] {
        pendingEntries.filter { entry in
            if statusFilter != "all" && statusFilter != "pending" { return false }
            if botFilter != "all" && entry.botId != botFilter { return false }
            if !query.isEmpty {
                let q = query.lowercased()
                guard entry.data.title?.lowercased().contains(q) == true
                    || entry.data.detail?.lowercased().contains(q) == true
                    || entry.data.command?.lowercased().contains(q) == true else { return false }
            }
            return true
        }
    }

    private var botOptions: [(String, String)] {
        var options: [(String, String)] = [("all", L("全部智能体"))]
        let names = Dictionary(store.audit.records.map { ($0.botId, $0.botName) },
                               uniquingKeysWith: { first, _ in first })
        for botId in names.keys.sorted() {
            options.append((botId, names[botId] ?? botId))
        }
        return options
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: L("审核记录"), trailing: AnyView(
                Button {
                    confirmClear = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.iconButton)
                .accessibilityLabel(L("清空记录"))
                .disabled(store.audit.records.isEmpty)
            ))
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.secondary)
                TextField(L("搜索记录"), text: $query)
                    .font(.body)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            HStack(spacing: 8) {
                ChoicePicker(selection: $statusFilter, options: [
                    ("all", L("全部状态")),
                    ("allowed", L("通过")),
                    ("denied", L("拒绝")),
                    ("pending", L("待决")),
                    ("done", L("已完成")),
                ])
                ChoicePicker(selection: $botFilter, options: botOptions)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            if filteredPending.isEmpty && filteredRecords.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "list.clipboard")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundStyle(Palette.tertiary)
                    Text(store.audit.records.isEmpty && pendingEntries.isEmpty ? L("还没有记录") : L("没有符合的记录"))
                        .font(.title3.weight(.semibold))
                    Text(L("智能体每做一件事、每一次审批决定，都会记在这里。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding(.horizontal, 32)
            } else {
                List {
                    if !filteredPending.isEmpty {
                        Section {
                            ForEach(filteredPending) { entry in
                                PendingAuditRow(entry: entry)
                            }
                        } header: {
                            Text(L("待决"))
                        }
                    }
                    if !filteredRecords.isEmpty {
                        Section {
                            ForEach(filteredRecords) { record in
                                Button {
                                    selected = record
                                } label: {
                                    AuditRow(record: record)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    store.audit.remove(id: filteredRecords[index].id)
                                }
                            }
                        } header: {
                            Text(L("记录"))
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(Palette.background)
        .codyncSheet(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            if let record = selected {
                NavigationStack { AuditDetailView(record: record) }
            }
        }
        .codyncDialog(
            isPresented: $confirmClear,
            title: L("清空全部记录？"),
            message: L("会删除全部审核记录，这个操作无法撤销。"),
            actions: [
                CodyncDialogAction(title: L("取消")) {},
                CodyncDialogAction(title: L("清空"), isDestructive: true) { store.audit.clear() },
            ]
        )
    }
}

private struct PendingAuditRow: View {
    var entry: Entry
    @EnvironmentObject private var store: AppStore
    @State private var answering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.data.title ?? entry.data.command ?? L("审批请求"))
                    .font(.body.weight(.medium))
                Spacer()
                Text(L("待决"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Text(botName)
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
            HStack(spacing: 8) {
                Button(L("允许")) { answer(allow: true) }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(answering)
                Button(L("拒绝")) { answer(allow: false) }
                    .buttonStyle(.bordered)
                    .disabled(answering)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 4)
    }

    private var botName: String {
        store.connector.mirror.bot(id: entry.botId)?.name ?? entry.botId
    }

    private func answer(allow: Bool) {
        let options = entry.data.options ?? []
        // Deny options are kind "reject_*"; allow options "allow_*".
        // No match means no answer — never answer the wrong thing.
        let option: PermissionOption?
        if allow {
            option = options.first(where: { $0.kind == "allow_once" })
                ?? options.first(where: { $0.kind.hasPrefix("allow") })
        } else {
            option = options.first(where: { $0.kind.hasPrefix("reject") })
        }
        guard let option else { return }
        answering = true
        Task {
            await store.answerApproval(entry: entry, option: option)
            answering = false
        }
    }
}

private struct AuditRow: View {
    var record: AuditRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.title)
                    .font(.body)
                    .lineLimit(2)
                Spacer()
                statusBadge
            }
            HStack(spacing: 6) {
                Text(record.botName)
                Text("·")
                Text(DateFormatter.chatTime.string(from: record.date))
            }
            .font(.caption)
            .foregroundStyle(Palette.secondary)
        }
        .padding(.vertical, 2)
    }

    private var statusBadge: some View {
        let label: String
        let color: Color
        switch record.status {
        case .allowed: label = L("通过"); color = .green
        case .denied: label = L("拒绝"); color = .red
        case .pending: label = L("待决"); color = .orange
        case .done: label = L("已完成"); color = Palette.secondary
        case .planned: label = L("计划"); color = Palette.secondary
        }
        return Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
    }
}

private struct AuditDetailView: View {
    var record: AuditRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                LabeledValue(label: L("智能体"), value: record.botName)
                LabeledValue(label: L("时间"), value: DateFormatter.auditTime.string(from: record.date))
                LabeledValue(label: L("类型"), value: kindLabel)
                LabeledValue(label: L("结果"), value: statusLabel)
            }
            Section {
                Text(record.title)
                    .font(.body)
                if !record.detail.isEmpty {
                    Text(record.detail)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                }
            } header: {
                Text(L("内容"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("记录详情"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("关闭")) { dismiss() }
            }
        }
    }

    private var kindLabel: String {
        switch record.kind {
        case .approval: return L("审批")
        case .decision: return L("提问")
        case .work: return L("工作")
        case .plan: return L("计划")
        }
    }

    private var statusLabel: String {
        switch record.status {
        case .allowed: return L("通过")
        case .denied: return L("拒绝")
        case .pending: return L("待决")
        case .done: return L("已完成")
        case .planned: return L("计划")
        }
    }
}

private struct LabeledValue: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(Palette.secondary)
            Spacer()
            Text(value)
        }
        .font(.body)
    }
}

// MARK: - Approvals

/// 审批: every pending approval across bots, answerable here, plus the
/// decided approval history from the audit log.
struct ApprovalsView: View {
    @EnvironmentObject private var store: AppStore

    private var pendingEntries: [Entry] {
        store.connector.mirror.bots.flatMap { bot in
            store.connector.mirror.entries(for: bot.id).filter { $0.isWaitingCard }
        }
    }

    private var decided: [AuditRecord] {
        store.audit.records.filter { $0.kind == .approval }
    }

    var body: some View {
        List {
            if pendingEntries.isEmpty {
                Text(L("没有待审批的请求。"))
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
            } else {
                Section {
                    ForEach(pendingEntries) { entry in
                        PendingAuditRow(entry: entry)
                    }
                } header: {
                    Text(L("待决"))
                }
            }
            if !decided.isEmpty {
                Section {
                    ForEach(decided) { record in
                        AuditRow(record: record)
                    }
                } header: {
                    Text(L("已决定"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("审批"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Upcoming

/// Upcoming: every routine across bots (title, next run, toggle, tap for
/// detail), their run history (failed runs retryable), and the bots'
/// waiting follow-ups (due time, cancellable). All rows come from
/// `store.routines`, which reads the host's `routines` listing — nothing
/// here is invented, and an empty host reads as an honest empty state.
struct UpcomingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var detailBotId: String?
    @State private var detailRoutineId: String?
    @State private var showingEditor = false
    @State private var editorBotId: String?
    @State private var editorRoutine: Routine?
    @State private var busyRoutineId: String?

    private var routines: [(botId: String, routine: Routine)] {
        store.routines.allRoutines
    }

    private var runs: [(botId: String, run: RoutineRun)] {
        store.routines.allRuns
    }

    private var followUps: [(botId: String, followUp: FollowUp)] {
        store.routines.allFollowUps
    }

    private var isEmpty: Bool {
        routines.isEmpty && runs.isEmpty && followUps.isEmpty
    }

    var body: some View {
        List {
            if isEmpty {
                Section {
                    Text(L("还没有定时任务。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                    Button {
                        editorBotId = store.leadBot?.id
                        editorRoutine = nil
                        showingEditor = true
                    } label: {
                        Label(L("新建定时任务"), systemImage: "plus")
                    }
                    .disabled(store.leadBot == nil || store.connector.api == nil)
                    if store.leadBot == nil {
                        Text(L("需要先配对电脑并有智能体。"))
                            .font(.footnote)
                            .foregroundStyle(Palette.secondary)
                    } else {
                        Button(L("请帮我新建一个定时任务")) {
                            store.draftToLeadBot(L("请帮我新建一个定时任务"))
                        }
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                    }
                } footer: {
                    Text(L("定时任务由电脑端按时执行，比如每天早上发简报。"))
                }
            } else {
                if !routines.isEmpty {
                    Section {
                        ForEach(routines.indices, id: \.self) { index in
                            routineRow(routines[index])
                        }
                    } header: {
                        Text(L("定时任务"))
                    }
                }
                if !runs.isEmpty {
                    Section {
                        ForEach(runs.indices, id: \.self) { index in
                            runRow(runs[index])
                        }
                    } header: {
                        Text(L("运行记录"))
                    }
                }
                if !followUps.isEmpty {
                    Section {
                        ForEach(followUps.indices, id: \.self) { index in
                            followUpRow(followUps[index])
                        }
                    } header: {
                        Text(L("稍后"))
                    }
                }
                Section {
                    Button {
                        editorBotId = store.leadBot?.id
                        editorRoutine = nil
                        showingEditor = true
                    } label: {
                        Label(L("新建定时任务"), systemImage: "plus")
                    }
                    .disabled(store.leadBot == nil || store.connector.api == nil)
                }
            }
            if let error = store.routines.lastError, !isEmpty {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("即将到来"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refresh()
        }
        .codyncSheet(isPresented: Binding(get: { detailRoutineId != nil }, set: { if !$0 { detailRoutineId = nil; detailBotId = nil } })) {
            if let botId = detailBotId, let routineId = detailRoutineId {
                NavigationStack { RoutineDetailView(botId: botId, routineId: routineId) }
            }
        }
        .codyncSheet(isPresented: $showingEditor) {
            if let botId = editorBotId {
                NavigationStack {
                    RoutineEditorView(botId: botId, routine: editorRoutine) { saved in
                        detailBotId = botId
                        detailRoutineId = saved.id
                    }
                }
            }
        }
    }

    private func routineRow(_ item: (botId: String, routine: Routine)) -> some View {
        HStack(spacing: 12) {
            Button {
                detailBotId = item.botId
                detailRoutineId = item.routine.id
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.routine.name)
                        .font(.body)
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Text(routineSubtitle(item))
                        .font(.caption)
                        .foregroundStyle(item.routine.lastError == nil ? Palette.secondary : Palette.danger)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(
                get: { item.routine.enabled },
                set: { newValue in setEnabled(item, enabled: newValue) }
            ))
            .labelsHidden()
            .toggleStyle(.codync)
            .disabled(busyRoutineId == item.routine.id)
        }
    }

    private func routineSubtitle(_ item: (botId: String, routine: Routine)) -> String {
        let botName = store.connector.mirror.bot(id: item.botId)?.name ?? item.botId
        if let lastError = item.routine.lastError {
            return lastError
        }
        if !item.routine.enabled {
            return "\(botName) · \(L("已关闭"))"
        }
        if let next = RoutineTime.nextRunText(item.routine.nextRunAt) {
            return "\(botName) · \(L("下次运行")) \(next)"
        }
        return botName
    }

    private func runRow(_ item: (botId: String, run: RoutineRun)) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.routines.routine(botId: item.botId, routineId: item.run.routineId)?.name ?? item.run.routineId)
                    .font(.body)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(runStatusText(item.run.status))
                    Text(RoutineTime.fullText(item.run.createdAt))
                }
                .font(.caption)
                .foregroundStyle(Palette.secondary)
                if let detail = item.run.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(2)
                }
                if let result = item.run.result, !result.isEmpty {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if item.run.isFailed {
                Button(L("重试")) { retryRun(item) }
                    .font(.subheadline.weight(.semibold))
                    .disabled(busyRoutineId == item.run.id)
            }
        }
    }

    private func followUpRow(_ item: (botId: String, followUp: FollowUp)) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.followUp.note)
                    .font(.body)
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
                Text(RoutineTime.fullText(item.followUp.at))
                    .font(.caption)
                    .foregroundStyle(Palette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(L("取消")) { cancelFollowUp(item) }
                .font(.subheadline.weight(.semibold))
                .disabled(busyRoutineId == item.followUp.id)
        }
    }

    private func refresh() async {
        guard let api = store.connector.api else { return }
        await store.routines.refreshAll(api: api, botIds: store.connector.mirror.bots.map(\.id), force: true)
    }

    private func setEnabled(_ item: (botId: String, routine: Routine), enabled: Bool) {
        guard let api = store.connector.api else { return }
        busyRoutineId = item.routine.id
        Task {
            _ = await store.routines.setEnabled(botId: item.botId, routineId: item.routine.id, enabled: enabled, api: api)
            await MainActor.run { busyRoutineId = nil }
        }
    }

    private func retryRun(_ item: (botId: String, run: RoutineRun)) {
        guard let api = store.connector.api else { return }
        busyRoutineId = item.run.id
        Task {
            _ = await store.routines.retryRun(botId: item.botId, runId: item.run.id, api: api)
            await MainActor.run { busyRoutineId = nil }
        }
    }

    private func cancelFollowUp(_ item: (botId: String, followUp: FollowUp)) {
        guard let api = store.connector.api else { return }
        busyRoutineId = item.followUp.id
        Task {
            _ = await store.routines.cancelFollowUp(botId: item.botId, followUpId: item.followUp.id, api: api)
            await MainActor.run { busyRoutineId = nil }
        }
    }
}
