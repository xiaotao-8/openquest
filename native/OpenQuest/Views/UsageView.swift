import SwiftUI

/// 用量统计（Minis Usage 页口径，ChatStore+UsageStats.swift：
/// 用量记录按消息记，归属按供应商/模型汇总；孤儿行不丢，归到“其他”）。
/// 累计 = 全部加起来；按日 = 最近 30 天按天列。
struct UsageView: View {
    @EnvironmentObject var store: AppStore
    @State private var mode = 0  // 0=累计，1=按日

    private var dayFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f
    }

    var body: some View {
        List {
            Picker("统计方式", selection: $mode) {
                Text("累计").tag(0)
                Text("按日").tag(1)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            Section("合计") {
                UsageRow(label: "输入", value: store.totalUsage.prompt)
                UsageRow(label: "输出", value: store.totalUsage.completion)
                HStack {
                    Text("总计")
                    Spacer()
                    Text("\(store.totalUsage.prompt + store.totalUsage.completion) tokens")
                        .font(.body.weight(.semibold))
                }
            }

            if mode == 1 {
                Section("按日（最近 30 天）") {
                    let days = store.usageByDay()
                    if days.isEmpty {
                        Text("还没有带用量的回复。聊过天之后，这里按天统计输入/输出。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(days, id: \.day) { row in
                        HStack {
                            Text(dayFormatter.string(from: row.day))
                            Spacer()
                            Text("入 \(row.prompt) · 出 \(row.completion)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("按供应商") {
                let rows = store.usageByProvider()
                if rows.isEmpty {
                    Text("还没有带用量的回复。聊过天之后，这里按供应商统计输入/输出。")
                        .foregroundStyle(.secondary)
                }
                ForEach(rows, id: \.name) { row in
                    HStack {
                        Text(row.name)
                        if row.estimated {
                            Text("估算").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("入 \(row.prompt) · 出 \(row.completion)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("按模型") {
                let rows = store.usageByModel()
                if rows.isEmpty {
                    Text("还没有带用量的回复。聊过天之后，这里按模型统计输入/输出。")
                        .foregroundStyle(.secondary)
                }
                ForEach(rows, id: \.name) { row in
                    HStack {
                        Text(row.name)
                        if row.estimated {
                            Text("估算").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("入 \(row.prompt) · 出 \(row.completion)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("按智能体") {
                if store.usageByAgent().isEmpty {
                    Text("还没有带用量的回复。聊过天之后，这里按智能体统计输入/输出。")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.usageByAgent(), id: \.name) { row in
                    HStack {
                        Text(row.name)
                        Spacer()
                        Text("入 \(row.prompt) · 出 \(row.completion)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Text("用量取每次回复的 SSE usage 段（输入/输出 token 数），存在每条回复下面；「估算」是没有当时供应商/模型快照的老记录，按发送智能体现在用的模型算的。换模型、清会话都会跟着变。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("用量统计")
    }
}

private struct UsageRow: View {
    let label: String
    let value: Int

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value) tokens")
        }
    }
}
