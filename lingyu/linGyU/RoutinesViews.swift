import SwiftUI

// MARK: - Formatting helpers (shared by Upcoming, detail, editor, State)

/// Next-run / run-time text. Today shows just the time; another day adds
/// the month and day. Digits only, so no localisation key is needed.
enum RoutineTime {
    static func nextRunText(_ ms: Int64?) -> String? {
        guard let ms else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M-d HH:mm"
        return formatter.string(from: date)
    }

    static func fullText(_ ms: Int64) -> String {
        DateFormatter.auditTime.string(from: Date(timeIntervalSince1970: TimeInterval(ms) / 1000))
    }
}

/// A run's status in words. Unknown host statuses are shown as-is.
func runStatusText(_ status: String) -> String {
    switch status {
    case "pending": return L("等待中")
    case "starting", "running", "recovering": return L("进行中")
    case "failed", "interrupted": return L("失败")
    case "done", "succeeded": return L("已完成")
    default: return status
    }
}

extension Routine {
    /// The row's second line: the host's trigger descriptions when it
    /// sent any, else a line built from the triggers themselves.
    var scheduleSummary: String {
        if !triggerDescriptions.isEmpty {
            return triggerDescriptions.joined(separator: " · ")
        }
        if triggers.isEmpty { return L("定时任务") }
        return triggers.map { triggerSummary($0) }.joined(separator: " · ")
    }
}

private func triggerSummary(_ trigger: RoutineTrigger) -> String {
    switch trigger.type {
    case "once":
        if let at = trigger.at { return RoutineTime.fullText(at) }
        return trigger.type
    case "cron":
        return trigger.expression ?? trigger.type
    case "interval":
        if let seconds = trigger.seconds { return "\(seconds) s" }
        return trigger.type
    case "event":
        return trigger.event ?? trigger.type
    default:
        return trigger.type
    }
}

// MARK: - Detail

/// One routine: a Rule tab (the rule as saved + its runs' trigger, timeout
/// and time zone) and a Run-history tab (every recorded run, failed ones
/// retryable). Looks the routine up live in the store, so a delete
/// elsewhere closes this sheet instead of showing a stale row.
struct RoutineDetailView: View {
    var botId: String
    var routineId: String
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var showingEditor = false
    @State private var showingDeleteDialog = false
    @State private var busy = false
    @State private var errorText: String?

    private var routine: Routine? {
        store.routines.routine(botId: botId, routineId: routineId)
    }

    private var tabs: [String] {
        [L("规则"), L("运行记录")]
    }

    var body: some View {
        if let routine {
            detailContent(routine)
        } else {
            VStack(spacing: 0) {
                ModalHeader(title: L("定时任务")) {
                    dismiss()
                }
                Text(L("还没有定时任务。"))
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 40)
                Spacer()
            }
            .background(Palette.background)
            .onAppear { dismiss() }
        }
    }

    private func detailContent(_ routine: Routine) -> some View {
        VStack(spacing: 0) {
            ModalHeader(title: routine.name, trailing: AnyView(
                Button(L("编辑")) { showingEditor = true }
                    .font(.body)
            )) {
                dismiss()
            }
            ScrollView {
                VStack(spacing: 20) {
                    TabChoice(titles: tabs, selection: $tab)
                    if tab == 0 {
                        ruleTab(routine)
                    } else {
                        runsTab(routine)
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.body)
                            .foregroundStyle(Palette.danger)
                    }
                    Button(L("删除"), role: .destructive) {
                        showingDeleteDialog = true
                    }
                    .foregroundStyle(Palette.danger)
                    .frame(maxWidth: .infinity)
                    .disabled(busy)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(Palette.background)
        .codyncSheet(isPresented: $showingEditor) {
            RoutineEditorView(botId: botId, routine: routine) { _ in
                showingEditor = false
            }
        }
        .codyncDialog(
            isPresented: $showingDeleteDialog,
            title: L("删除这个定时任务？"),
            message: L("删除后，它的定时运行都会停止，且无法恢复。"),
            actions: [
                CodyncDialogAction(title: L("取消")) {},
                CodyncDialogAction(title: L("删除"), isDestructive: true) {
                    deleteRoutine(routine)
                },
            ]
        )
    }

    private func ruleTab(_ routine: Routine) -> some View {
        VStack(spacing: 20) {
            CardSection(title: L("规则")) {
                CardRow {
                    ValueRow(label: L("名字"), value: routine.name)
                }
                Hairline()
                CardRow {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("指令"))
                            .foregroundStyle(Palette.text)
                        Text(routine.instruction)
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondary)
                    }
                }
                Hairline()
                CardRow {
                    ValueRow(label: L("触发"), value: routine.scheduleSummary)
                }
                Hairline()
                CardRow {
                    ValueRow(label: L("超时（秒）"), value: "\(routine.timeoutSeconds ?? 3600)")
                }
                Hairline()
                CardRow {
                    ValueRow(label: L("时区"), value: routine.triggers.first?.timeZone ?? TimeZone.current.identifier)
                }
                if let next = RoutineTime.nextRunText(routine.nextRunAt) {
                    Hairline()
                    CardRow {
                        ValueRow(label: L("下次运行"), value: next)
                    }
                }
            }
            CardSection(title: L("状态")) {
                CardRow {
                    Toggle(routine.enabled ? L("已开启") : L("已关闭"), isOn: Binding(
                        get: { routine.enabled },
                        set: { newValue in setEnabled(routine, enabled: newValue) }
                    ))
                    .toggleStyle(.codync)
                    .disabled(busy)
                }
                if let lastError = routine.lastError {
                    CardRow {
                        Text(lastError)
                            .font(.subheadline)
                            .foregroundStyle(Palette.danger)
                    }
                }
            }
        }
    }

    private func runsTab(_ routine: Routine) -> some View {
        let runs = store.routines.runs(for: routine.id)
        return CardSection(title: L("运行记录")) {
            if runs.isEmpty {
                CardRow {
                    Text(L("还没有定时任务。"))
                        .foregroundStyle(Palette.secondary)
                }
            } else {
                ForEach(runs.indices, id: \.self) { index in
                    let item = runs[index]
                    CardRow {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(runStatusText(item.run.status))
                                    .font(.body)
                                    .foregroundStyle(Palette.text)
                                Text(RoutineTime.fullText(item.run.createdAt))
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
                                Button(L("重试")) { retryRun(item.run) }
                                    .font(.subheadline.weight(.semibold))
                                    .disabled(busy)
                            }
                        }
                    }
                    if item.run.id != runs.last?.run.id {
                        Hairline()
                    }
                }
            }
        }
    }

    private func setEnabled(_ routine: Routine, enabled: Bool) {
        guard let api = store.connector.api else { return }
        busy = true
        Task {
            let ok = await store.routines.setEnabled(botId: botId, routineId: routine.id, enabled: enabled, api: api)
            await MainActor.run {
                busy = false
                errorText = ok ? nil : L("保存失败，请重试。")
            }
        }
    }

    private func retryRun(_ run: RoutineRun) {
        guard let api = store.connector.api else { return }
        busy = true
        Task {
            let ok = await store.routines.retryRun(botId: botId, runId: run.id, api: api)
            await MainActor.run {
                busy = false
                errorText = ok ? nil : L("保存失败，请重试。")
            }
        }
    }

    private func deleteRoutine(_ routine: Routine) {
        guard let api = store.connector.api else { return }
        busy = true
        Task {
            let ok = await store.routines.delete(botId: botId, routineId: routine.id, api: api)
            await MainActor.run {
                busy = false
                if ok {
                    dismiss()
                } else {
                    errorText = L("删除失败，请重试。")
                }
            }
        }
    }
}

// MARK: - Editor

/// New / edit routine. Triggers are built on this phone from five
/// frequencies (once / hourly / daily / weekdays / weekly / custom cron);
/// the time zone is always the device time zone. Saving replaces the
/// routine's triggers with the single trigger built here — a routine the
/// bot set up with a webhook or event trigger loses that trigger on
/// save, because this editor cannot show it.
struct RoutineEditorView: View {
    var botId: String
    var routine: Routine?
    var onSaved: (Routine) -> Void
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var instruction: String
    @State private var frequency: String
    @State private var onceDate: Date
    @State private var timeOfDay: Date
    @State private var minute: Int
    @State private var weekday: Int
    @State private var cronExpression: String
    @State private var timeoutText: String
    @State private var saving = false
    @State private var errorText: String?
    @State private var showingDeleteDialog = false

    private var frequencies: [(id: String, label: String)] {
        [
            (id: "once", label: L("一次")),
            (id: "hourly", label: L("每小时")),
            (id: "daily", label: L("每天")),
            (id: "weekdays", label: L("工作日")),
            (id: "weekly", label: L("每周")),
            (id: "custom", label: L("自定")),
        ]
    }

    init(botId: String, routine: Routine?, onSaved: @escaping (Routine) -> Void) {
        self.botId = botId
        self.routine = routine
        self.onSaved = onSaved
        var frequency = "daily"
        var onceDate = Date().addingTimeInterval(3600)
        var timeOfDay = Date(timeIntervalSinceReferenceDate: 9 * 3600)
        var minute = 0
        var weekday = 1
        var cronExpression = "0 9 * * 1-5"
        if let routine, routine.triggers.count == 1, let trigger = routine.triggers.first {
            switch trigger.type {
            case "once":
                if let at = trigger.at {
                    frequency = "once"
                    onceDate = Date(timeIntervalSince1970: TimeInterval(at) / 1000)
                }
            case "cron":
                if let expression = trigger.expression {
                    let parsed = Self.parseCron(expression)
                    frequency = parsed.frequency
                    timeOfDay = parsed.timeOfDay
                    minute = parsed.minute
                    weekday = parsed.weekday
                    cronExpression = expression
                }
            default:
                break
            }
        }
        _name = State(initialValue: routine?.name ?? "")
        _instruction = State(initialValue: routine?.instruction ?? "")
        _frequency = State(initialValue: frequency)
        _onceDate = State(initialValue: onceDate)
        _timeOfDay = State(initialValue: timeOfDay)
        _minute = State(initialValue: minute)
        _weekday = State(initialValue: weekday)
        _cronExpression = State(initialValue: cronExpression)
        _timeoutText = State(initialValue: "\(routine?.timeoutSeconds ?? 3600)")
    }

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: routine == nil ? L("新建定时任务") : L("编辑定时任务")) {
                dismiss()
            }
            ScrollView {
                VStack(spacing: 24) {
                    CardSection(title: L("名字")) {
                        CardRow {
                            TextField(L("名字"), text: $name)
                                .onChange(of: name) { _, newValue in
                                    if newValue.count > 120 {
                                        name = String(newValue.prefix(120))
                                    }
                                }
                        }
                    }
                    CardSection(title: L("指令")) {
                        CardRow {
                            TextField(L("指令"), text: $instruction, axis: .vertical)
                                .lineLimit(3...8)
                        }
                    }
                    CardSection(title: L("触发")) {
                        CardRow {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L("触发"))
                                    .foregroundStyle(Palette.text)
                                ChoicePicker(selection: $frequency, options: frequencies)
                            }
                        }
                        Hairline()
                        CardRow {
                            triggerFields
                        }
                        Hairline()
                        CardRow {
                            ValueRow(label: L("时区"), value: TimeZone.current.identifier)
                        }
                    }
                    CardSection(title: L("超时（秒）")) {
                        CardRow {
                            HStack {
                                Text(L("超时（秒）"))
                                    .foregroundStyle(Palette.text)
                                Spacer()
                                TextField("", text: $timeoutText)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 96)
                            }
                        }
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.body)
                            .foregroundStyle(Palette.danger)
                    }
                    PrimaryActionButton(
                        title: saving ? L("保存") : (routine == nil ? L("创建") : L("保存")),
                        isEnabled: !saving
                    ) {
                        save()
                    }
                    if routine != nil {
                        Button(L("删除"), role: .destructive) {
                            showingDeleteDialog = true
                        }
                        .foregroundStyle(Palette.danger)
                        .frame(maxWidth: .infinity)
                        .disabled(saving)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(Palette.background)
        .codyncDialog(
            isPresented: $showingDeleteDialog,
            title: L("删除这个定时任务？"),
            message: L("删除后，它的定时运行都会停止，且无法恢复。"),
            actions: [
                CodyncDialogAction(title: L("取消")) {},
                CodyncDialogAction(title: L("删除"), isDestructive: true) {
                    deleteRoutine()
                },
            ]
        )
    }

    @ViewBuilder
    private var triggerFields: some View {
        switch frequency {
        case "once":
            VStack(alignment: .leading, spacing: 8) {
                Text(L("时间"))
                    .foregroundStyle(Palette.text)
                DatePicker("", selection: $onceDate)
                    .labelsHidden()
            }
        case "hourly":
            VStack(alignment: .leading, spacing: 8) {
                Text(L("分钟"))
                    .foregroundStyle(Palette.text)
                ChoicePicker(selection: $minute, options: (0..<60).map { (id: $0, label: String(format: ":%02d", $0)) })
            }
        case "daily", "weekdays":
            VStack(alignment: .leading, spacing: 8) {
                Text(L("时间"))
                    .foregroundStyle(Palette.text)
                DatePicker("", selection: $timeOfDay, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .environment(\.timeZone, Self.gmt)
            }
        case "weekly":
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("星期"))
                        .foregroundStyle(Palette.text)
                    ChoicePicker(selection: $weekday, options: [1, 2, 3, 4, 5, 6, 0].map {
                        (id: $0, label: Calendar.current.standaloneWeekdaySymbols[$0])
                    })
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("时间"))
                        .foregroundStyle(Palette.text)
                    DatePicker("", selection: $timeOfDay, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .environment(\.timeZone, Self.gmt)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Cron 表达式"))
                    .foregroundStyle(Palette.text)
                TextField(L("0 9 * * 1-5"), text: $cronExpression)
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
    }

    /// The single trigger the form builds, or nil when the custom cron
    /// does not have five space-separated fields.
    private var builtTrigger: RoutineTrigger? {
        let timeZone = TimeZone.current.identifier
        let (hour, minuteOfHour) = Self.hourMinute(of: timeOfDay)
        switch frequency {
        case "once":
            return RoutineTrigger(type: "once", at: Int64((onceDate.timeIntervalSince1970 * 1000).rounded()), timeZone: timeZone)
        case "hourly":
            return RoutineTrigger(type: "cron", expression: "\(minute) * * * *", timeZone: timeZone)
        case "daily":
            return RoutineTrigger(type: "cron", expression: "\(minuteOfHour) \(hour) * * *", timeZone: timeZone)
        case "weekdays":
            return RoutineTrigger(type: "cron", expression: "\(minuteOfHour) \(hour) * * 1-5", timeZone: timeZone)
        case "weekly":
            return RoutineTrigger(type: "cron", expression: "\(minuteOfHour) \(hour) * * \(weekday)", timeZone: timeZone)
        default:
            let parts = cronExpression.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count == 5 else { return nil }
            return RoutineTrigger(type: "cron", expression: parts.joined(separator: " "), timeZone: timeZone)
        }
    }

    private func save() {
        guard let api = store.connector.api else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedInstruction.isEmpty else {
            errorText = L("请先填写标题和指令。")
            return
        }
        guard let trigger = builtTrigger else {
            errorText = L("Cron 表达式须有 5 段，用空格分开。")
            return
        }
        if frequency == "once", onceDate <= Date() {
            errorText = L("触发时间已过，请选一个未来的时间。")
            return
        }
        guard let timeout = Int(timeoutText), (1...86400).contains(timeout) else {
            errorText = L("超时须在 1 秒到 24 小时之间。")
            return
        }
        saving = true
        errorText = nil
        Task {
            do {
                let saved = try await store.routines.save(
                    botId: botId, routineId: routine?.id, name: trimmedName,
                    instruction: trimmedInstruction, triggers: [trigger],
                    timeoutSeconds: timeout, api: api)
                await MainActor.run {
                    saving = false
                    onSaved(saved)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    saving = false
                    errorText = L("保存失败，请重试。")
                }
            }
        }
    }

    private func deleteRoutine() {
        guard let routine, let api = store.connector.api else { return }
        saving = true
        Task {
            let ok = await store.routines.delete(botId: botId, routineId: routine.id, api: api)
            await MainActor.run {
                saving = false
                if ok {
                    dismiss()
                } else {
                    errorText = L("删除失败，请重试。")
                }
            }
        }
    }

    // MARK: - Cron parsing (editor round-trip)

    private static var gmt: TimeZone {
        TimeZone(secondsFromGMT: 0) ?? .current
    }

    private static func hourMinute(of date: Date) -> (Int, Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = gmt
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 9, components.minute ?? 0)
    }

    /// Splits a cron expression back into the frequency it came from, so
    /// editing a saved routine reopens on the same frequency. Anything
    /// unrecognised opens as custom with the expression kept verbatim.
    private static func parseCron(_ expression: String) -> (frequency: String, timeOfDay: Date, minute: Int, weekday: Int) {
        let fallback = (frequency: "custom", timeOfDay: Date(timeIntervalSinceReferenceDate: 9 * 3600), minute: 0, weekday: 1)
        let parts = expression.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 5,
              let minutePart = Int(parts[0]),
              (0..<60).contains(minutePart),
              parts[2] == "*", parts[3] == "*" else {
            return fallback
        }
        if parts[1] == "*", parts[4] == "*" {
            return (frequency: "hourly", timeOfDay: fallback.timeOfDay, minute: minutePart, weekday: 1)
        }
        guard let hourPart = Int(parts[1]), (0..<24).contains(hourPart) else {
            return fallback
        }
        let timeOfDay = Date(timeIntervalSinceReferenceDate: TimeInterval(hourPart * 3600 + minutePart * 60))
        switch parts[4] {
        case "*":
            return (frequency: "daily", timeOfDay: timeOfDay, minute: minutePart, weekday: 1)
        case "1-5":
            return (frequency: "weekdays", timeOfDay: timeOfDay, minute: minutePart, weekday: 1)
        default:
            if let weekdayPart = Int(parts[4]), (0...6).contains(weekdayPart) {
                return (frequency: "weekly", timeOfDay: timeOfDay, minute: minutePart, weekday: weekdayPart)
            }
            return fallback
        }
    }
}
