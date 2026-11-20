import SwiftUI

/// 提问卡 / 投票卡 bottom sheet（FishPocket question.png 的样子 + Minis user_ask 的规矩）：
/// 小灰标题 + 大号粗体问题 + 浅灰选项容器（单选圆圈/多选方框，第一个打“推荐”），
/// 固定行：你来定 / 其他 / 添加备注；黑底 Commit + 灰字 Skip。
/// 超时只给建议、不自动执行（到期由聊天页的 checkCardExpiry 结算，这里不抢）。
struct AskSheetView: View {
    let card: CardPayload
    let onAnswer: ([CardOption]) -> Void
    let onSkip: () -> Void
    /// 用户在卡上点了一下：聊天页把倒计时重开（Minis noteInteraction，
    /// 人在就重算；不传就是不重开，卡片本身照常）。
    var onInteract: () -> Void = {}
    @State private var page = 0
    @State private var pagePicked: [Int: Set<String>] = [:]
    /// Other / 备注 / 开放式答案 / 你来定 都是按题存的草稿（Minis
    /// UserAskAnswer 按题一份）：翻页不丢，提交时各题自己带走。
    @State private var pageOther: [Int: String] = [:]
    @State private var pageNote: [Int: String] = [:]
    @State private var pageOpen: [Int: String] = [:]
    @State private var pageDelegated: Set<Int> = []

    private var pages: [CardPayload] { [card] + card.extraQuestions }
    private var current: CardPayload { pages[min(page, pages.count - 1)] }
    private var isLastPage: Bool { page >= pages.count - 1 }
    private var isOpenQuestion: Bool { current.options.isEmpty }

    /// 本页的小标签：每题自己的 header，没有就用首题的（Minis header 按题给，≤12 字）。
    private var pageHeader: String {
        let h = current.header.isEmpty ? card.header : current.header
        return String(h.prefix(12))
    }

    /// 本页的推荐项：模型给的 default（recommendedId）优先，没有就第一个
    /// （Minis timeoutSuggestion 也是 default 优先、否则首选）。
    private func recommendedIdForPage(_ p: Int) -> String {
        let q = pages[p]
        if !q.recommendedId.isEmpty, q.options.contains(where: { $0.id == q.recommendedId }) { return q.recommendedId }
        return q.options.first?.id ?? ""
    }

    private var recommendedId: String { recommendedIdForPage(page) }

    private func isRecommended(_ opt: CardOption) -> Bool {
        !recommendedId.isEmpty && opt.id == recommendedId
    }

    private func isSelected(_ opt: CardOption) -> Bool {
        (pagePicked[page] ?? []).contains(opt.id)
    }

    /// 本题算不算答完（Minis UserAskAnswer.isComplete）：选了 / 写了 Other /
    /// 写了开放式答案 / 点了你来定，任一即可；向导的下一题/提交按这个放行。
    private func isPageComplete(_ p: Int) -> Bool {
        if pageDelegated.contains(p) { return true }
        let q = pages[p]
        if q.options.isEmpty {
            return !(pageOpen[p] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !(pagePicked[p] ?? []).isEmpty { return true }
        return !(pageOther[p] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 本题的答案行：选中的选项 + Other 自写（多选可与选项并存）；
    /// 你来定是一行 __youdecide__；开放式题的答案走 __other__。
    private func optionsForPage(_ p: Int) -> [CardOption] {
        if pageDelegated.contains(p) { return [CardOption(id: "__youdecide__", label: "你来定")] }
        let q = pages[p]
        var out: [CardOption] = []
        if q.options.isEmpty {
            let v = (pageOpen[p] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { out.append(CardOption(id: "__other__", label: v)) }
            return out
        }
        out += q.options.filter { (pagePicked[p] ?? []).contains($0.id) }
        let v = (pageOther[p] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !v.isEmpty { out.append(CardOption(id: "__other__", label: v)) }
        return out
    }

    private func radioIcon(for opt: CardOption) -> String {
        let sel = isSelected(opt)
        if current.multiSelect { return sel ? "checkmark.square.fill" : "square" }
        return sel ? "largecircle.fill.circle" : "circle"
    }

    /// 提交：各题的备注（有才加，__note__）附在答案后，交给 onAnswer。
    private func submit(_ opts: [CardOption]) {
        var all = opts
        for p in pages.indices {
            let note = (pageNote[p] ?? "").trimmingCharacters(in: .whitespaces)
            if !note.isEmpty {
                all.append(CardOption(id: "__note__", label: "备注：\(note)"))
            }
        }
        onAnswer(all)
    }

    private func allPickedOptions() -> [CardOption] {
        var out: [CardOption] = []
        for idx in pages.indices { out += optionsForPage(idx) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(Palette.control).frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                Text(pageHeader.isEmpty ? (card.kind == .vote ? "投票" : "提问") : pageHeader)
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
                TextField("写下你的回答…", text: Binding(
                    get: { pageOpen[page] ?? "" },
                    set: { pageOpen[page] = $0 }
                ), axis: .vertical)
                    .lineLimit(1...4)
                    .padding(12)
                    .background(Palette.field, in: RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(current.options.enumerated()), id: \.element.id) { idx, opt in
                        if idx > 0 { Divider().background(Palette.stroke).padding(.leading, 52) }
                        Button {
                            onInteract()
                            pageDelegated.remove(page)
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
                                        if isRecommended(opt) {
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
            // 提问卡固定尾行（每题都有，Minis 卡片标配）：你来定 / 其他 / 补充说明。
            // 单题时点你来定/发送立即提交；向导里先记成本题答案，翻页/提交时带走。
            if card.kind == .ask && !isOpenQuestion {
                Button {
                    onInteract()
                    if pages.count == 1 {
                        submit([CardOption(id: "__youdecide__", label: "你来定")])
                    } else {
                        pageDelegated.insert(page)
                        pagePicked[page] = []
                        if isLastPage { submit(allPickedOptions()) } else { page += 1 }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: pageDelegated.contains(page)
                              ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 19))
                            .foregroundStyle(pageDelegated.contains(page)
                                             ? Palette.ink : Palette.faint)
                            .frame(width: 22)
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
                    TextField("其他：自己写答案", text: Binding(
                        get: { pageOther[page] ?? "" },
                        set: { pageOther[page] = $0 }
                    ))
                        .font(.system(size: 16))
                    if pages.count == 1 {
                        Button("发送") {
                            onInteract()
                            let v = (pageOther[page] ?? "").trimmingCharacters(in: .whitespaces)
                            guard !v.isEmpty else { return }
                            submit([CardOption(id: "__other__", label: v)])
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .disabled((pageOther[page] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(.vertical, 8)
            }
            if card.kind == .ask {
                HStack(spacing: 8) {
                    Image(systemName: (pageNote[page] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                          ? "plus" : "note.text")
                        .font(.system(size: 14.5))
                        .foregroundStyle(Palette.secondary)
                    TextField("补充说明（随答案一起发）", text: Binding(
                        get: { pageNote[page] ?? "" },
                        set: { pageNote[page] = $0 }
                    ))
                        .font(.system(size: 14.5))
                }
                .padding(.vertical, 6)
            }
            if current.multiSelect || pages.count > 1 {
                HStack(spacing: 10) {
                    if page > 0 {
                        Button("上一题") { onInteract(); page -= 1 }
                            .secondaryCapsule()
                    }
                    Button(isLastPage ? "提交" : "下一题") {
                        onInteract()
                        if isLastPage { submit(allPickedOptions()) }
                        else { page += 1 }
                    }
                    .primaryCapsule()
                    .disabled(!isPageComplete(page))
                }
            } else {
                Button("提交") { submit(optionsForPage(page)) }
                    .primaryCapsule()
                    .disabled(!isPageComplete(page))
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
        .onAppear {
            // 原版 FP question.png：首选（Recommended）打开就是选中态（实心黑圆），
            // 提交直接可用；单选卡每题默认选中推荐项，多选/开放式不动。
            // 点“你来定”会清掉本页选择（已有逻辑），不影响默认选中。
            for p in pages.indices {
                let q = pages[p]
                guard !q.options.isEmpty, !q.multiSelect, (pagePicked[p] ?? []).isEmpty else { continue }
                let r = recommendedIdForPage(p)
                if !r.isEmpty { pagePicked[p] = [r] }
            }
        }
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
