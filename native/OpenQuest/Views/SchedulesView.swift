import SwiftUI

/// 定时任务（FishPocket 式）：按智能体或按群，到点发一条指令开工。
/// iOS 诚实做法：本地通知 + 打开 App 后执行到期的任务（后台常驻跑不了，不假装）。
struct SchedulesView: View {
    @EnvironmentObject var store: AppStore
    @State private var showingAdd = false

    var body: some View {
        List {
            if store.scheduledTasks.isEmpty {
                Text("还没有定时任务。定一个：到点自动给智能体（或群）发一条指令，它就开工。App 在前台时直接执行；App 关着时先响通知，你点开就执行。")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.scheduledTasks) { t in
                HStack(spacing: 11) {
                    Image(systemName: "alarm.fill")
                        .foregroundStyle(t.enabled ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title)
                        Text("\(t.targetName) · \(repeatText(t))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("下次：\(t.nextFire.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { t.enabled },
                        set: { store.setScheduledTaskEnabled(id: t.id, $0) }
                    ))
                    .labelsHidden()
                }
            }
            .onDelete { idx in
                for i in idx { store.deleteScheduledTask(id: store.scheduledTasks[i].id) }
            }
            Section {
                Text("后台说明：iOS 不让 App 在后台常驻跑活。任务到点时先响本地通知，App 打开后立刻执行，不会悄悄丢掉。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("定时任务")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) { AddScheduleView() }
    }

    private func repeatText(_ t: ScheduledTask) -> String {
        switch t.repeatKind {
        case "once": return "一次"
        case "daily": return "每天 \(t.time)"
        case "weekly":
            let names = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]
            let days = t.weekdays.sorted().map { names[$0] }.joined(separator: "、")
            return "\(days) \(t.time)"
        case "every": return "每 \(t.everyMinutes) 分钟"
        default: return t.repeatKind
        }
    }
}

private struct AddScheduleView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var targetKind = "agent"
    @State private var targetId: UUID?
    @State private var title = ""
    @State private var prompt = ""
    @State private var repeatKind = "once"
    @State private var time = Date()
    @State private var onceDate = Date().addingTimeInterval(3600)
    @State private var weekdays: Set<Int> = [1, 2, 3, 4, 5]
    @State private var everyMinutes = 60

    private var targets: [(id: UUID, name: String)] {
        if targetKind == "agent" {
            return store.agents.map { ($0.id, $0.name) }
        }
        return store.conversations.filter { $0.isGroup }.map { ($0.id, $0.title) }
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: time)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("给谁") {
                    Picker("对象", selection: $targetKind) {
                        Text("智能体").tag("agent")
                        Text("群聊").tag("room")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: targetKind) { _, _ in targetId = nil }
                    Picker(targetKind == "agent" ? "智能体" : "群聊", selection: $targetId) {
                        Text("选一个").tag(nil as UUID?)
                        ForEach(targets, id: \.id) { t in
                            Text(t.name).tag(t.id as UUID?)
                        }
                    }
                    if targets.isEmpty {
                        Text(targetKind == "agent" ? "还没有智能体，先建一个。" : "还没有群聊，先建一个群。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("到点做什么") {
                    TextField("名字，如：每天早报", text: $title)
                    TextEditor(text: $prompt)
                        .frame(minHeight: 80)
                }
                Section("什么时候") {
                    Picker("重复", selection: $repeatKind) {
                        Text("一次").tag("once")
                        Text("每天").tag("daily")
                        Text("每周").tag("weekly")
                        Text("每 N 分钟").tag("every")
                    }
                    .pickerStyle(.segmented)
                    if repeatKind == "once" {
                        DatePicker("时间", selection: $onceDate)
                    }
                    if repeatKind == "daily" || repeatKind == "weekly" {
                        DatePicker("时间", selection: $time, displayedComponents: .hourAndMinute)
                    }
                    if repeatKind == "weekly" {
                        HStack {
                            ForEach(1...7, id: \.self) { d in
                                let names = ["", "一", "二", "三", "四", "五", "六", "日"]
                                Button(names[d]) {
                                    if weekdays.contains(d) { weekdays.remove(d) }
                                    else { weekdays.insert(d) }
                                }
                                .frame(width: 30, height: 30)
                                .background(weekdays.contains(d) ? Color.blue : Color.white.opacity(0.1),
                                            in: Circle())
                                .foregroundStyle(weekdays.contains(d) ? .white : .primary)
                            }
                        }
                    }
                    if repeatKind == "every" {
                        Stepper("每 \(everyMinutes) 分钟", value: $everyMinutes, in: 5...10080, step: 5)
                    }
                }
            }
            .navigationTitle("新建定时任务")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveTask() }
                        .disabled(targetId == nil
                                  || title.trimmingCharacters(in: .whitespaces).isEmpty
                                  || prompt.trimmingCharacters(in: .whitespaces).isEmpty
                                  || (repeatKind == "weekly" && weekdays.isEmpty))
                }
            }
        }
    }

    private func saveTask() {
        guard let tid = targetId else { return }
        let name = targets.first { $0.id == tid }?.name ?? ""
        let first = AppStore.firstFire(repeatKind: repeatKind, time: timeString,
                                       weekdays: Array(weekdays).sorted(),
                                       everyMinutes: everyMinutes,
                                       at: repeatKind == "once" ? onceDate : Date())
        let t = ScheduledTask(
            targetKind: targetKind, targetId: tid, targetName: name,
            title: title.trimmingCharacters(in: .whitespaces),
            prompt: prompt.trimmingCharacters(in: .whitespaces),
            repeatKind: repeatKind, time: timeString,
            weekdays: Array(weekdays).sorted(), everyMinutes: everyMinutes,
            nextFire: first)
        store.addScheduledTask(t)
        dismiss()
    }
}
