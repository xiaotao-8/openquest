import SwiftUI

/// 提问卡 / 投票卡 bottom sheet（FishPocket question.png 的样子 + Minis user_ask 的规矩）：
/// 小灰标题 + 大号粗体问题 + 浅灰选项容器（单选圆圈/多选方框，第一个打“推荐”），
/// 固定行：你来定 / 其他 / 添加备注；黑底 Commit + 灰字 Skip。
/// 超时只给建议、不自动执行（到期由聊天页的 checkCardExpiry 结算，这里不抢）。
struct AskSheetView: View {
    let card: CardPayload
    let onAnswer: ([CardOption]) -> Void
    let onSkip: () -> Void
    @State private var page = 0
    @State private var pagePicked: [Int: Set<String>] = [:]
    @State private var otherText = ""
    @State private var noteText = ""
    @State private var openAnswer = ""

    private var pages: [CardPayload] { [card] + card.extraQuestions }
    private var current: CardPayload { pages[min(page, pages.count - 1)] }
    private var isLastPage: Bool { page >= pages.count - 1 }
    private var isOpenQuestion: Bool { current.options.isEmpty }

    private func isSelected(_ opt: CardOption) -> Bool {
        (pagePicked[page] ?? []).contains(opt.id)
    }

    private func radioIcon(for opt: CardOption) -> String {
        let sel = isSelected(opt)
        if current.multiSelect { return sel ? "checkmark.square.fill" : "square" }
        return sel ? "largecircle.fill.circle" : "circle"
    }

    private func submit(_ opts: [CardOption]) {
        var all = opts
        let note = noteText.trimmingCharacters(in: .whitespaces)
        if !note.isEmpty {
            all.append(CardOption(id: "__note__", label: "备注：\(note)"))
        }
        onAnswer(all)
    }

    private func allPickedOptions() -> [CardOption] {
        var out: [CardOption] = []
        for (idx, q) in pages.enumerated() {
            let set = pagePicked[idx] ?? []
            out += q.options.filter { set.contains($0.id) }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(Palette.control).frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                Text(card.header.isEmpty ? (card.kind == .vote ? "投票" : "提问") : card.header)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                Spacer()
                if pages.count > 1 {
                    Text("\(page + 1)/\(pages.count)")
                        .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(Palette.secondary)
                }
                SheetCountdown(deadline: card.deadline)
            }
            Text(current.question)
                .font(.system(size: 22, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            if isOpenQuestion {
                TextField("写下你的回答…", text: $openAnswer, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(12)
                    .background(Palette.field, in: RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(current.options.enumerated()), id: \.element.id) { idx, opt in
                        if idx > 0 { Divider().background(Palette.stroke).padding(.leading, 52) }
                        Button {
                            var set = pagePicked[page] ?? []
                            if current.multiSelect {
                                if set.contains(opt.id) { set.remove(opt.id) }
                                else { set.insert(opt.id) }
                                pagePicked[page] = set
                            } else {
                                pagePicked[page] = [opt.id]
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: radioIcon(for: opt))
                                    .font(.system(size: 19))
                                    .foregroundStyle(isSelected(opt) ? Palette.ink : Palette.faint)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(opt.label)
                                            .font(.system(size: 16, weight: isSelected(opt) ? .semibold : .regular))
                                            .foregroundStyle(Palette.ink)
                                        if idx == 0 {
                                            Text("推荐")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(Palette.secondary)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Palette.control, in: Capsule())
                                        }
                                    }
                                    if !opt.detail.isEmpty {
                                        Text(opt.detail)
                                            .font(.system(size: 13.5))
                                            .foregroundStyle(Palette.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .background(Palette.field, in: RoundedRectangle(cornerRadius: 20))
            }
            // 提问卡专属行（单题时）：你来定 / 其他 / 补充说明。
            if card.kind == .ask && pages.count == 1 {
                Button { submit([CardOption(id: "__youdecide__", label: "你来定")]) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "circle").font(.system(size: 19))
                            .foregroundStyle(Palette.faint).frame(width: 22)
                        Text("你来定").font(.system(size: 16)).foregroundStyle(Palette.ink)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                HStack(spacing: 10) {
                    Image(systemName: "circle").font(.system(size: 19))
                        .foregroundStyle(Palette.faint).frame(width: 22)
                    TextField("其他：自己写答案", text: $otherText)
                        .font(.system(size: 16))
                    Button("发送") {
                        let v = otherText.trimmingCharacters(in: .whitespaces)
                        guard !v.isEmpty else { return }
                        submit([CardOption(id: "__other__", label: v)])
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .disabled(otherText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.vertical, 8)
                HStack(spacing: 8) {
                    Image(systemName: noteText.trimmingCharacters(in: .whitespaces).isEmpty
                          ? "plus" : "note.text")
                        .font(.system(size: 14.5))
                        .foregroundStyle(Palette.secondary)
                    TextField("补充说明（随答案一起发）", text: $noteText)
                        .font(.system(size: 14.5))
                }
                .padding(.vertical, 6)
            }
            if current.multiSelect || pages.count > 1 {
                HStack(spacing: 10) {
                    if page > 0 {
                        Button("上一题") { page -= 1 }
                            .secondaryCapsule()
                    }
                    Button(isLastPage ? "提交" : "下一题") {
                        if isLastPage { submit(allPickedOptions()) }
                        else { page += 1 }
                    }
                    .primaryCapsule()
                    .disabled((pagePicked[page] ?? []).isEmpty)
                }
            } else {
                Button("提交") {
                    if isOpenQuestion {
                        let v = openAnswer.trimmingCharacters(in: .whitespaces)
                        guard !v.isEmpty else { return }
                        submit([CardOption(id: "__other__", label: v)])
                    } else {
                        let picked = current.options.filter { isSelected($0) }
                        submit(picked)
                    }
                }
                .primaryCapsule()
                .disabled(isOpenQuestion
                          ? openAnswer.trimmingCharacters(in: .whitespaces).isEmpty
                          : (pagePicked[page] ?? []).isEmpty)
            }
            Button("跳过", action: onSkip)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 28)
        .fittedSheet()
    }
}

/// 审批卡 bottom sheet（FishPocket approval.png 的样子 + Minis confirm 的规矩）：
/// 标题 + 说明（可展开）+ 等宽代码块（可滚动）+ 影响行 + 风险色，
/// 拒绝（浅灰）/ 允许（黑，高风险时红）并排。
struct ApprovalSheetView: View {
    let card: CardPayload
    let onAnswer: ([CardOption]) -> Void
    let onSkip: () -> Void
    @State private var denyReason = ""
    @State private var showMore = false

    private var approveOption: CardOption {
        card.options.first { $0.id == "approve" } ?? CardOption(id: "approve", label: "批准")
    }
    private var rejectOption: CardOption {
        card.options.first { $0.id == "reject" } ?? CardOption(id: "reject", label: "拒绝")
    }

    private var riskText: String? {
        switch card.risk {
        case "high": return "高风险"
        case "medium": return "中等风险"
        default: return nil
        }
    }

    private var riskColor: Color {
        card.risk == "high" ? .red : .orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(Palette.control).frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                Text(card.actionText.isEmpty ? card.question : "允许运行这条命令？")
                    .font(.system(size: 20, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                SheetCountdown(deadline: card.deadline)
            }
            if let risk = riskText {
                Text(risk)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(riskColor)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(riskColor.opacity(0.14), in: Capsule())
            }
            if !card.actionText.isEmpty, !card.question.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(showMore || card.question.count <= 120
                         ? card.question : String(card.question.prefix(120)) + "…")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if card.question.count > 120 {
                        Button(showMore ? "收起" : "显示更多") { showMore.toggle() }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.ink)
                    }
                }
            }
            if !card.actionText.isEmpty {
                ScrollView {
                    Text(card.actionText)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
                .padding(12)
                .background(Palette.field, in: RoundedRectangle(cornerRadius: 12))
            }
            if !card.impact.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(riskColor)
                    Text(card.impact)
                        .font(.system(size: 14.5))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Image(systemName: denyReason.trimmingCharacters(in: .whitespaces).isEmpty
                      ? "plus" : "arrow.uturn.backward")
                    .font(.system(size: 14.5))
                    .foregroundStyle(Palette.secondary)
                TextField("取消原因 / 改成怎么做", text: $denyReason)
                    .font(.system(size: 14.5))
            }
            .padding(.vertical, 6)
            HStack(spacing: 10) {
                Button("拒绝") {
                    var opts = [rejectOption]
                    let r = denyReason.trimmingCharacters(in: .whitespaces)
                    if !r.isEmpty {
                        opts.append(CardOption(id: "__deny_reason__", label: "取消原因：\(r)"))
                    }
                    onAnswer(opts)
                }
                .secondaryCapsule()
                Button("允许") { onAnswer([approveOption]) }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.onInk)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(card.risk == "high" ? Color.red : Palette.ink, in: Capsule())
            }
            Button("跳过", action: onSkip)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 28)
        .fittedSheet()
    }
}

/// 倒计时小标签：m:ss（无“剩余”二字），≤30 秒变琥珀；到期不抢结算，等聊天页处理。
struct SheetCountdown: View {
    let deadline: Date?
    @State private var now = Date()

    var body: some View {
        if let deadline {
            let left = Int(deadline.timeIntervalSince(now))
            Label(left <= 0 ? "已超时" : "\(left / 60):\(String(format: "%02d", left % 60))",
                  systemImage: "timer")
                .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                .foregroundStyle(left <= 30 ? Palette.waiting : Palette.secondary)
                .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
        }
    }
}
