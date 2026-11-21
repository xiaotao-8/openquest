import ActivityKit
import SwiftUI
import UserNotifications
import WidgetKit

// MARK: - Bot activity presentation

/// The state a Live Activity / Dynamic Island shows for one bot.
/// Presentation only; no ActivityKit payload lives here.
struct BotActivityPresentation: Hashable, Sendable {
    enum Phase: Hashable, Sendable {
        /// `sending` and `queued` are this phone's own (a message on its
        /// way, or waiting in the relay mailbox for an offline computer);
        /// the computer only pushes the others.
        case sending, queued, working, needsInput, completed, failed, stale, waiting
        /// This phone is on a call with the bot (original: onCall carries
        /// the call state). Phase 1 has no voice calls, so nothing sets
        /// this yet; it exists so the call layer can, and so the symbol
        /// map matches the original.
        case onCall
    }

    let phase: Phase
    let activity: String

    init(status: String, activity: String, isStale: Bool = false) {
        let phase: Phase = switch status {
        case "sending": .sending
        case "queued": .queued
        case "working": .working
        case "needsInput": .needsInput
        case "idle", "completed": .completed
        case "error": .failed
        case "onCall": .onCall
        default: .waiting
        }
        self.phase = isStale && (phase == .working || phase == .needsInput || phase == .sending) ? .stale : phase
        self.activity = activity
    }

    var title: String {
        switch phase {
        case .sending: return L("发送中")
        case .queued: return L("等待电脑")
        case .working: return L("进行中")
        case .needsInput: return L("需要你确认")
        case .completed: return L("已完成")
        case .failed: return L("失败")
        case .stale: return L("更新延迟")
        case .waiting: return L("等待更新")
        case .onCall: return L("通话中")
        }
    }

    /// The one line of text beside the orb: the bot's current step while
    /// it's live, else the state.
    var caption: String {
        switch phase {
        case .working, .needsInput: return activity.isEmpty ? title : activity
        case .sending, .queued, .completed, .failed, .stale, .waiting, .onCall: return title
        }
    }

    /// Original BotActivityPresentation.symbol: onCall → waveform.
    var symbol: String {
        switch phase {
        case .completed: return "checkmark"
        case .failed: return "exclamationmark.triangle.fill"
        case .queued: return "desktopcomputer"
        case .onCall: return "waveform"
        case .sending, .working, .needsInput, .stale, .waiting: return "ellipsis"
        }
    }
}

extension BotActivityPresentation {
    var orbState: ThinkingOrb.OrbState? {
        switch phase {
        case .working: return .working
        case .needsInput: return .listening
        case .onCall: return .listening
        case .sending, .waiting, .stale: return .connecting
        case .queued, .completed, .failed: return nil
        }
    }

    var tint: Color {
        switch phase {
        case .needsInput: return Palette.attention
        case .failed: return Palette.danger
        case .completed: return Palette.added
        case .sending, .queued, .stale, .waiting: return Palette.secondary
        case .working, .onCall: return Palette.text
        }
    }

    /// The caption stays quiet while the bot works and takes the state's color otherwise.
    var captionTint: Color { phase == .working ? Palette.secondary : tint }

    /// How many of the progress line's four segments are filled.
    var progressStep: Int {
        switch phase {
        case .sending, .queued: return 1
        case .working, .stale, .waiting, .onCall: return 2
        case .needsInput: return 3
        case .completed, .failed: return 4
        }
    }

    var mood: CharacterAvatar.Mood {
        switch phase {
        case .working: return .working
        case .needsInput: return .needsInput
        case .sending, .queued, .completed, .failed, .stale, .waiting, .onCall: return .idle
        }
    }

    /// The elapsed time counts up on its own (no push) while the bot works.
    func elapsedStart(_ startedAt: Date?) -> Date? {
        phase == .working || phase == .needsInput ? startedAt : nil
    }
}

extension AnyTransition {
    /// Rows a new phase brings (the Review button, the timer): rise and fade in.
    static var activityRow: AnyTransition {
        .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity)
    }
}

/// A bot the user named stays as they wrote it.
func widgetName(_ bot: Bot) -> String { bot.name }

extension Bot {
    /// The state word the widgets show and its color: only what needs you
    /// (or failed) stands out.
    var widgetState: (label: String, tint: Color) {
        if needsYouOutside { return (L("需要你确认"), Palette.attention) }
        if status == "error" { return (L("失败"), Palette.danger) }
        if isBusyOutside { return (L("进行中"), Palette.text) }
        return (L("就绪"), Palette.secondary)
    }
}

// MARK: - Activity cards

/// The bot's face in its phase's mood. On a phase change the bot itself
/// moves: the halftone highlight sweeps to the new side and the eyes
/// glance over (or the ripple appears).
struct ActivityAvatar: View {
    let shape: String
    let color: String
    let state: BotActivityPresentation
    let size: CGFloat
    let botId: String?
    @ObservedObject private var avatarStore = AvatarStore.shared

    init(shape: String, color: String, state: BotActivityPresentation, size: CGFloat, botId: String? = nil) {
        self.shape = shape
        self.color = color
        self.state = state
        self.size = size
        self.botId = botId
    }

    var body: some View {
        if let botId, let photo = avatarStore.photo(for: botId) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(AvatarClipShape(shape: AvatarShape(rawValue: shape) ?? .blob))
        } else {
            CharacterAvatar(shape: shape, color: color, size: size, mood: state.mood, still: true)
                .animation(Motion.activityPhase, value: state.mood)
        }
    }
}

/// The step (or state) in its color, then the running time.
struct ActivityCaption: View {
    let state: BotActivityPresentation
    let startedAt: Date?

    init(state: BotActivityPresentation, startedAt: Date?) {
        self.state = state
        self.startedAt = startedAt
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(state.caption)
                .foregroundStyle(state.captionTint)
                .contentTransition(.interpolate)
                .layoutPriority(1)
            // No fixedSize on a timer Text: a Live Activity can't lay one
            // out at its ideal width and draws the whole card black.
            // Unconstrained, it takes the width left over.
            if let since = state.elapsedStart(startedAt) {
                Text("·").foregroundStyle(Palette.tertiary)
                Text(since, style: .timer).monospacedDigit().foregroundStyle(Palette.secondary)
            }
        }
        .font(.system(size: 12))
        .lineLimit(1)
    }
}

/// The bot's progress: four segments that fill as it moves, in the state's color.
struct ActivityProgress: View {
    let state: BotActivityPresentation

    init(state: BotActivityPresentation) { self.state = state }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { index in
                Capsule().fill(index < state.progressStep ? state.tint : state.tint.opacity(0.16))
            }
        }
        .frame(height: 6)
    }
}

/// Opens the conversation on the request; approval itself stays on the permission card.
struct ActivityReviewButton: View {
    let state: BotActivityPresentation
    let link: URL?

    init(state: BotActivityPresentation, link: URL?) {
        self.state = state
        self.link = link
    }

    var body: some View {
        if let link { Link(destination: link) { label } } else { label }
    }

    private var label: some View {
        Label(L("查看"), systemImage: "hand.raised.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(state.tint, in: Capsule())
    }
}

/// Shared by the Lock Screen Live Activity and the in-app gallery. The
/// Live Activity passes its own face and mark; the gallery uses the still ones.
struct BotActivityCard<Face: View, Mark: View>: View {
    let name: String
    let state: BotActivityPresentation
    let startedAt: Date?
    let link: URL?
    let face: Face
    let mark: Mark

    init(name: String, state: BotActivityPresentation, startedAt: Date? = nil, link: URL? = nil,
         @ViewBuilder face: () -> Face, @ViewBuilder mark: () -> Mark) {
        self.name = name
        self.state = state
        self.startedAt = startedAt
        self.link = link
        self.face = face()
        self.mark = mark()
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                face
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                    ActivityCaption(state: state, startedAt: startedAt)
                }
                Spacer(minLength: 8)
                mark
            }
            ActivityProgress(state: state)
            if state.phase == .needsInput {
                ActivityReviewButton(state: state, link: link).transition(.activityRow)
            }
        }
        .padding(16)
        .animation(Motion.activityPhase, value: state)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(state.title). \(state.caption). \(L("进度，第 %d 步，共 4 步", state.progressStep))")
    }
}

extension BotActivityCard where Face == ActivityAvatar, Mark == BotActivityIndicator {
    init(bot: Bot, state: BotActivityPresentation, startedAt: Date? = nil) {
        self.init(name: widgetName(bot), state: state, startedAt: startedAt) {
            ActivityAvatar(shape: bot.avatarShape, color: bot.avatarColor, state: state, size: 32, botId: bot.id)
        } mark: {
            BotActivityIndicator(state: state, size: 28)
        }
    }
}

/// The state mark: a thinking orb while the bot works, a symbol once it has
/// ended (errors and delayed updates never look complete).
struct BotActivityIndicator: View {
    let state: BotActivityPresentation
    let size: CGFloat

    init(state: BotActivityPresentation, size: CGFloat = 20) {
        self.state = state
        self.size = size
    }

    var body: some View {
        // The orb and the end symbols cross-fade; the bot beside it carries the motion.
        ZStack {
            Group {
                if let orb = state.orbState {
                    ThinkingOrb(state: orb, size: size, color: state.tint, animated: false)
                } else {
                    Image(systemName: state.symbol).font(.system(size: size * 0.6, weight: .semibold))
                }
            }
            .id(state.phase)
            .transition(.opacity)
        }
        .frame(width: size, height: size)
        .foregroundStyle(state.tint)
        .animation(Motion.activityPhase, value: state.phase)
        .accessibilityElement()
        .accessibilityLabel(state.title)
    }
}

/// The expanded island's bottom row: Review while the bot needs you, else the running time.
struct ActivityIslandFooter: View {
    let state: BotActivityPresentation
    let startedAt: Date?
    let link: URL?

    init(state: BotActivityPresentation, startedAt: Date?, link: URL?) {
        self.state = state
        self.startedAt = startedAt
        self.link = link
    }

    var body: some View {
        Group {
            if state.phase == .needsInput {
                ActivityReviewButton(state: state, link: link)
            } else if let since = state.elapsedStart(startedAt) {
                // The timer alone, centered on its own: a timer Text reserves
                // its widest width, so beside an icon (or interpolated with
                // one) it sat off center.
                Text(since, style: .timer)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .transition(.activityRow)
        .animation(Motion.activityPhase, value: state)
    }
}

/// Illustrations for the gallery: the real Dynamic Island's regions and
/// camera cutout are laid out by iOS.
struct BotActivityPreview: View {
    enum Form: String, CaseIterable {
        case lockScreen = "Lock Screen", compact = "Compact", minimal = "Minimal", expanded = "Expanded"

        var title: String {
            switch self {
            case .lockScreen: return L("锁屏")
            case .compact: return L("紧凑")
            case .minimal: return L("极简")
            case .expanded: return L("展开")
            }
        }
    }

    let bot: Bot
    let state: BotActivityPresentation
    let form: Form
    let startedAt: Date?

    init(bot: Bot, state: BotActivityPresentation, form: Form, startedAt: Date? = nil) {
        self.bot = bot
        self.state = state
        self.form = form
        self.startedAt = startedAt
    }

    var body: some View {
        Group {
            if form == .lockScreen {
                BotActivityCard(bot: bot, state: state, startedAt: startedAt)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
            } else {
                island.environment(\.colorScheme, .dark)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(form.rawValue) preview")
    }

    @ViewBuilder private var island: some View {
        switch form {
        case .compact:
            HStack {
                islandFace(20)
                Spacer(minLength: 70)
                BotActivityIndicator(state: state)
            }
            .padding(.horizontal, 12).frame(width: 210, height: 38)
            .background(.black, in: Capsule())
        case .minimal:
            BotActivityIndicator(state: state)
                .frame(width: 38, height: 38).background(.black, in: Circle())
        case .expanded:
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    islandFace(26)
                    VStack(spacing: 2) {
                        Text(widgetName(bot)).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        Text(state.caption).font(.system(size: 12)).foregroundStyle(state.captionTint)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    BotActivityIndicator(state: state, size: 28)
                }
                ActivityIslandFooter(state: state, startedAt: startedAt, link: nil)
            }
            .padding(18).background(.black, in: RoundedRectangle(cornerRadius: 28))
        case .lockScreen: EmptyView()
        }
    }

    /// The island plays the working bot's loop; here the live avatar stands in for it.
    @ViewBuilder private func islandFace(_ size: CGFloat) -> some View {
        if state.phase == .working {
            CharacterAvatar(shape: bot.avatarShape, color: bot.avatarColor, size: size, mood: .working)
        } else {
            ActivityAvatar(shape: bot.avatarShape, color: bot.avatarColor, state: state, size: size, botId: bot.id)
        }
    }
}

// MARK: - Widget cards

/// A usage provider's icon (original ProviderMascot): the provider's logo
/// asset when the style is "original" and one exists, else the provider's
/// first-letter disc — never `chart.bar`. No `agent-*` logo assets ship in
/// linGyU yet, so the "original" style renders the first-letter disc until
/// logo assets are added. The logo name follows the original: claude/codex
/// run through ACP adapters (`agent-<id>-acp`), others go by their own id.
struct ProviderMascot: View {
    let providerId: String
    let providerName: String
    let size: CGFloat
    var style: String = "character"

    private var logoAsset: String? {
        let registry = ["claude", "codex"].contains(providerId) ? "\(providerId)-acp" : providerId
        let name = "agent-\(registry)"
        return UIImage(named: name) == nil ? nil : name
    }

    var body: some View {
        Group {
            if style == "original", let logo = logoAsset {
                Image(logo).resizable().scaledToFit().padding(size * 0.08)
            } else {
                Text(String(providerName.prefix(1)))
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Palette.avatarColor(named: "gray"), in: Circle())
            }
        }
        .frame(width: size, height: size)
    }
}

/// The usage widget preview. The `usage` RPC does not exist yet, so this
/// shows the card's chrome with an honest empty state — never a number.
struct UsagePreviewCard: View {
    enum Layout { case small, medium, large }

    let providerName: String
    let providerId: String
    let layout: Layout
    let iconStyle: String

    init(providerName: String, providerId: String = "", layout: Layout, iconStyle: String = "character") {
        self.providerName = providerName
        self.providerId = providerId
        self.layout = layout
        self.iconStyle = iconStyle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: layout == .small ? 6 : 8) {
            HStack(spacing: 7) {
                if iconStyle == "character" {
                    CharacterAvatar(shape: "hex", color: "gray", size: 22, still: true)
                } else {
                    ProviderMascot(providerId: providerId, providerName: providerName, size: 22, style: iconStyle)
                }
                Text(providerName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if layout != .small {
                    Text(L("用量"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("暂无用量数据"))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
                Text(L("连接电脑后，这里会按供应商显示用量。"))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Fine, separated ticks keep low and high usage legible without a heavy gauge.
struct UsageTicks: View {
    let percent: Double
    let tint: Color
    let height: CGFloat

    init(percent: Double, tint: Color, height: CGFloat = 16) {
        self.percent = percent
        self.tint = tint
        self.height = height
    }

    var body: some View {
        GeometryReader { geometry in
            let count = max(1, Int(geometry.size.width / 4))
            let value = percent.isFinite ? min(100, max(0, percent)) : 0
            let filled = Int((Double(count) * value / 100).rounded())
            let color = value >= 90 ? Palette.danger : tint
            HStack(spacing: 1.5) {
                ForEach(0..<count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < filled ? color : color.opacity(0.16))
                }
            }
        }
        .frame(height: height)
        .accessibilityLabel(L("用量"))
        .accessibilityValue(L("%d%%", Int((percent.isFinite ? percent : 0).rounded())))
    }
}

struct BotsWidgetCard: View {
    let bots: [Bot]
    let wide: Bool
    let large: Bool

    init(bots: [Bot], wide: Bool, large: Bool = false) {
        self.bots = bots.filter { !$0.hidden }
        self.wide = wide
        self.large = large
    }

    private var ordered: [Bot] {
        bots.sorted {
            let rank: (Bot) -> Int = { $0.needsYouOutside ? 0 : $0.isBusyOutside ? 1 : 2 }
            return rank($0) == rank($1) ? $0.lastAt > $1.lastAt : rank($0) < rank($1)
        }
    }

    private var needs: Int { bots.filter(\.needsYouOutside).count }
    private var working: Int { bots.filter { $0.isBusyOutside && !$0.needsYouOutside }.count }
    private var count: Int { needs > 0 ? needs : working > 0 ? working : bots.count }
    private var label: String {
        needs > 0 ? L("需要你确认") : working > 0 ? L("进行中") : bots.isEmpty ? L("还没有智能体") : L("一切正常")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("智能体")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            if large {
                HStack {
                    summary
                    Spacer()
                    Text(L("共 %d 个 · %d 个在干活", bots.count, working))
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                Divider()
                botRows(limit: 6)
                Spacer(minLength: 0)
            } else if wide {
                HStack(alignment: .center, spacing: 16) {
                    summary.frame(width: 76, alignment: .leading)
                    Rectangle().fill(Palette.border).frame(width: 1)
                    botRows(limit: 3)
                }
            } else {
                Spacer(minLength: 0)
                summary
                HStack(spacing: -4) {
                    ForEach(ordered.prefix(3)) { bot in
                        CharacterAvatar(bot: bot, size: 23, still: true)
                    }
                    Spacer(minLength: 0)
                    if working > 0 && needs > 0 {
                        Text(L("%d 个在干活", working)).font(.system(size: 9)).foregroundStyle(Palette.secondary)
                    }
                }
            }
        }
        .foregroundStyle(Palette.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(Motion.activityPhase, value: bots)
    }

    private func botRows(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ordered.prefix(limit)) { bot in
                row(bot)
                    .transition(.activityRow)
            }
            if bots.isEmpty {
                Text(L("在 linGyU 里新建第一个智能体。"))
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(count)").font(.system(size: 36, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(needs > 0 ? Palette.attention : Palette.text)
                .contentTransition(.numericText(value: Double(count)))
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary)
                .contentTransition(.interpolate)
        }
        .accessibilityElement(children: .combine)
    }

    /// Name and step on the left, the state on the right in its color.
    private func row(_ bot: Bot) -> some View {
        let state = bot.widgetState
        return HStack(spacing: 7) {
            CharacterAvatar(bot: bot, size: 24, still: true)
            VStack(alignment: .leading, spacing: 1) {
                Text(widgetName(bot)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.text)
                if bot.isBusyOutside, !bot.outsideLine.isEmpty {
                    Text(bot.outsideLine).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        .contentTransition(.interpolate)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            Text(state.label)
                .font(.system(size: 10, weight: bot.needsYouOutside ? .semibold : .regular))
                .foregroundStyle(state.tint)
                .lineLimit(1)
                .contentTransition(.interpolate)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The new-conversation widget's in-app preview: a plus mark, the
/// kind, and the lead bot it will open a chat with (or the honest empty
/// state when there is no bot yet). Tapping it in the real widget opens
/// the new chat; here it is a preview only.
struct NewConversationPreviewCard: View {
    let leadBot: Bot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Palette.text)
            Spacer(minLength: 0)
            Text(L("新建"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.text)
            if let leadBot {
                HStack(spacing: 6) {
                    CharacterAvatar(bot: leadBot, size: 20, still: true)
                    Text(widgetName(leadBot))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
            } else {
                Text(L("还没有智能体"))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(Palette.text)
    }
}

/// The MiniApps widget's in-app preview: the user's Spaces, up to four
/// rows, or the honest empty state with the create entry.
struct MiniAppsPreviewCard: View {
    let spaces: [SpaceItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("小工具")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            .foregroundStyle(Palette.text)
            if spaces.isEmpty {
                Spacer(minLength: 0)
                Text(L("还没有小工具"))
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Text(L("描述一个来创建"))
                    .font(.system(size: 10)).foregroundStyle(Palette.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(spaces.prefix(4)) { space in
                        HStack(spacing: 8) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.secondary)
                                .frame(width: 24, height: 24)
                                .background(Palette.bubbleAgent, in: RoundedRectangle(cornerRadius: 7))
                            Text(space.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Palette.text)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Palette.tertiary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Four bots in a 2×2 grid, each in its mood with a dot for its state.
/// Spots picked in the widget's settings keep their bot; the rest fill
/// with the bots that need you first, and empty spots hold a faded
/// sleeping character.
struct BotsTeamCard: View {
    let slots: [Bot?]

    init(bots: [Bot], picks: [String?] = []) {
        slots = Self.slots(bots: bots, picks: picks)
    }

    /// The bots in their four spots: picks first (a deleted pick falls back to automatic).
    static func slots(bots: [Bot], picks: [String?]) -> [Bot?] {
        let byId = Dictionary(bots.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let picked = (0..<4).map { i in i < picks.count ? picks[i].flatMap { byId[$0] } : nil }
        let taken = Set(picked.compactMap { $0?.id })
        var queue = bots.filter { !$0.hidden && !taken.contains($0.id) }.sorted {
            let rank: (Bot) -> Int = { $0.needsYouOutside ? 0 : $0.isBusyOutside ? 1 : 2 }
            return rank($0) == rank($1) ? $0.lastAt > $1.lastAt : rank($0) < rank($1)
        }[...]
        return picked.map { $0 ?? queue.popFirst() }
    }

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow { tile(0); tile(1) }
            GridRow { tile(2); tile(3) }
        }
        .animation(Motion.activityPhase, value: slots)
    }

    @ViewBuilder private func tile(_ index: Int) -> some View {
        if let bot = slots[index] {
            botTile(bot)
        } else {
            CharacterAvatar(shape: "blob", color: "gray", size: 26)
                .opacity(0.18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.bubbleAgent.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)
        }
    }

    private func botTile(_ bot: Bot) -> some View {
        VStack(spacing: 4) {
            CharacterAvatar(bot: bot, size: 30, still: true)
            Text(widgetName(bot))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bubbleAgent, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            if bot.isBusyOutside || bot.status == "error" {
                Circle().fill(bot.widgetState.tint).frame(width: 7, height: 7).padding(7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(widgetName(bot)), \(bot.widgetState.label)")
    }
}

/// Monochrome Lock Screen widgets; the system supplies the background and tint.
struct AccessoryWidgetCard: View {
    enum Kind { case bots, usage }
    enum Family: String, CaseIterable { case circular = "Circle", rectangular = "Rectangle", inline = "Inline" }

    /// The highest reported usage window, if the computer reported any.
    struct TopUsage {
        var providerName: String
        var percent: Double
        var title: String
        var resetsText: String?
    }

    let kind: Kind
    let family: Family
    let bots: [Bot]
    let topUsage: TopUsage?
    let paired: Bool

    init(kind: Kind, family: Family, bots: [Bot] = [], topUsage: TopUsage? = nil, paired: Bool = true) {
        self.kind = kind
        self.family = family
        self.bots = bots.filter { !$0.hidden }
        self.topUsage = topUsage
        self.paired = paired
    }

    private var needs: Int { bots.filter(\.needsYouOutside).count }
    private var working: Int { bots.filter { $0.isBusyOutside && !$0.needsYouOutside }.count }
    private var count: Int { needs > 0 ? needs : working > 0 ? working : bots.count }
    private var botLabel: String {
        needs > 0 ? L("个需要你确认") : working > 0 ? L("个在干活") : L("个智能体")
    }

    private var headline: String {
        guard paired else { return L("连接一台电脑") }
        if kind == .bots { return bots.isEmpty ? L("还没有智能体") : "\(count) \(botLabel)" }
        return topUsage.map { "\($0.providerName) \(Int($0.percent.rounded()))%" } ?? L("暂无用量数据")
    }

    var body: some View {
        Group {
            switch family {
            case .inline:
                Label(headline, systemImage: kind == .bots ? "bubble.left.and.bubble.right" : "chart.bar")
                    .font(.caption).lineLimit(1)
            case .circular:
                if !paired {
                    Image(systemName: "desktopcomputer").accessibilityLabel(headline)
                } else if kind == .usage, let top = topUsage {
                    Gauge(value: min(100, max(0, top.percent)), in: 0...100) {
                        Text(top.providerName.prefix(2))
                    } currentValueLabel: {
                        Text("\(Int(top.percent.rounded()))").font(.system(size: 18, weight: .semibold))
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .accessibilityLabel(headline)
                } else {
                    VStack(spacing: 0) {
                        Text(kind == .bots ? "\(count)" : "—").font(.system(size: 24, weight: .semibold, design: .rounded))
                        Text(kind == .bots ? (needs > 0 ? L("需要你确认") : working > 0 ? L("进行中") : L("个智能体")) : L("用量"))
                            .font(.system(size: 9))
                    }
                }
            case .rectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if paired, kind == .bots {
                        ForEach(bots.sorted { rank($0) < rank($1) }.prefix(2)) { bot in
                            Text("\(widgetName(bot)) · \(bot.needsYouOutside ? L("需要你确认") : bot.isBusyOutside ? L("进行中") : L("就绪"))")
                                .font(.system(size: 10)).lineLimit(1)
                        }
                    } else if paired, let top = topUsage {
                        Text(top.title).font(.system(size: 10)).lineLimit(1)
                        if let resetsText = top.resetsText {
                            Text(resetsText).font(.system(size: 9)).lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func rank(_ bot: Bot) -> Int { bot.needsYouOutside ? 0 : bot.isBusyOutside ? 1 : 2 }
}

// MARK: - Widget gallery

/// The State tab's Widget page. The installed widgets and these previews
/// share their rendering components.
struct WidgetGalleryView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var page: Page?
    @State private var kind = "roster"
    @State private var size = "medium"
    @State private var hasWidget: Bool?
    @State private var widgetCheckFailed = false
    /// Whether the add-widget steps are shown (the preview's tap target).
    @State private var showWidgetSteps = false
    /// nil until asked, false once turned off in the Settings app.
    @State private var notificationsAllowed: Bool?
    @AppStorage("cn.lingyu.usageIconStyle") private var usageIconStyle = "character"

    private var bots: [Bot] { store.connector.mirror.bots }

    /// The lead bot, for the new-conversation preview.
    private var leadBot: Bot? { store.connector.mirror.leadBot }

    private var spaces: [SpaceItem] { store.spaces.spaces }

    /// The widgets this extension actually ships: the roster, a new
    /// conversation, and MiniApps. (The usage and team previews stay in
    /// this file as components, but their widgets are not built in this
    /// round, so they are not offered here.)
    private var kinds: [(id: String, label: String)] {
        [("roster", L("智能体")), ("new", L("新建")), ("miniapps", L("小工具"))]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    CharacterAvatar(shape: "hex", color: "gray", size: 42)
                        .frame(width: 58, height: 58)
                        .background(Palette.bubbleUser, in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("linGyU，一目了然。"))
                            .font(.title3.weight(.semibold)).tracking(-0.4)
                        Text(L("你的智能体和用量，处处可见。"))
                            .font(.footnote).foregroundStyle(Palette.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))

                VStack(alignment: .leading, spacing: 9) {
                    sectionLabel(L("准备工作"))
                    VStack(spacing: 0) {
                        setupRow(L("连接一台电脑"), complete: store.connector.isPaired)
                        Rectangle().fill(Palette.border).frame(height: 0.5).padding(.leading, 42)
                        setupRow(L("添加一个 linGyU 小组件"), complete: hasWidget == true,
                                 status: hasWidget == nil ? (widgetCheckFailed ? L("无法检查") : L("检查中")) : nil)
                        Rectangle().fill(Palette.border).frame(height: 0.5).padding(.leading, 42)
                        Button(action: turnOnNotifications) {
                            setupRow(notificationsAllowed == false ? L("在设置里打开通知") : L("打开通知"),
                                     complete: notificationsAllowed == true)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(notificationsAllowed == true)
                        .accessibilityHint(L("智能体做完或需要你时能收到通知。"))
                    }
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                    if widgetCheckFailed {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("没能检查你的小组件。你仍可以按下面的步骤添加。"))
                                .foregroundStyle(Palette.secondary)
                            Button(L("再检查一次")) { checkWidgets() }
                                .buttonStyle(.secondary)
                        }
                        .font(.caption)
                    } else {
                        Text(hasWidget == nil ? L("正在检查你的小组件…") : L("做完一步，这里会自动打勾。"))
                            .font(.caption2).foregroundStyle(Palette.tertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        sectionLabel(L("选一个小组件"))
                        Spacer()
                        Text(L("示例数据")).font(.caption2).foregroundStyle(Palette.secondary)
                    }
                    if typeSize.isAccessibilitySize {
                        ChoicePicker(selection: $kind, options: kinds)
                    } else {
                        SegmentedChoice(options: kinds.map { (value: $0.id, title: $0.label) }, selection: $kind)
                    }
                    if kind == "roster" {
                        ChoicePicker(selection: $size, options: [("small", L("小")), ("medium", L("中")), ("large", L("大"))])
                    }
                    VStack(spacing: 18) {
                        preview(wide: size != "small")
                            .frame(width: kind == "roster" && size != "small" ? nil : 158, height: kind == "roster" && size == "large" ? 338 : 158)
                        previewDescription
                        Button { showWidgetSteps.toggle() } label: {
                            HStack {
                                Text(L("怎么添加 linGyU 小组件"))
                                    .font(.footnote.weight(.medium))
                                Spacer()
                                Image(systemName: showWidgetSteps ? "chevron.up" : "chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Palette.tertiary)
                            }
                            .foregroundStyle(Palette.text)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(L("长按主屏幕上的空白处"))
                        if showWidgetSteps {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(WidgetSetupDemo.steps, id: \.index) { step in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("\(step.index + 1)")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(Palette.secondary)
                                            .frame(width: 16, height: 16)
                                            .background(Palette.surface, in: Circle())
                                        Text(step.text)
                                            .font(.footnote)
                                            .foregroundStyle(Palette.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(14)
                    .background(Palette.bubbleAgent, in: RoundedRectangle(cornerRadius: 26))
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel(L("选一个外观"))
                    SegmentedChoice(options: [("character", L("小人")), ("original", L("原始图标"))], selection: Binding(
                        get: { usageIconStyle },
                        set: { usageIconStyle = $0; WidgetCenter.shared.reloadTimelines(ofKind: "linGyUProviderUsage") }
                    ))
                    Text(L("对应用内和桌面小组件里的用量都生效。"))
                        .font(.caption).foregroundStyle(Palette.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel(L("让任务一直在眼前"))
                    Button { page = .lockScreen } label: {
                        Label(L("锁屏小组件"), systemImage: "lock.rectangle").foregroundStyle(Palette.accent)
                    }
                    .buttonStyle(PressScale())
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel(L("添加小组件"))
                    WidgetSetupDemo(bots: bots)
                }
                Text(L("小组件显示最新上报。打开 linGyU 看实时更新和审批。"))
                    .font(.caption2).foregroundStyle(Palette.tertiary)
            }
            .padding(18)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        .background(Palette.background)
        .navigationDestination(item: $page) { page in
            switch page {
            case .lockScreen: LockWidgetGalleryView()
            }
        }
        .task {
            checkWidgets()
            await checkNotifications()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            checkWidgets()
            Task { await checkNotifications() }
        }
    }

    private enum Page: Hashable { case lockScreen }

    private var previewDescription: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(previewTitle).font(.subheadline.weight(.medium))
            Text(previewBody)
                .font(.caption).foregroundStyle(Palette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var previewTitle: String {
        switch kind {
        case "new": return L("新建")
        case "miniapps": return L("小工具")
        default: return L("%@尺寸小组件", size == "small" ? L("小") : size == "large" ? L("大") : L("中"))
        }
    }

    private var previewBody: String {
        switch kind {
        case "new": return leadBot?.name ?? L("还没有智能体")
        case "miniapps": return spaces.isEmpty ? L("还没有小工具") : spaces[0].title
        default: return L("看谁需要你、谁还在干活。大尺寸最多显示六个智能体。")
        }
    }

    @ViewBuilder private func preview(wide: Bool) -> some View {
        Group {
            if kind == "miniapps" {
                MiniAppsPreviewCard(spaces: spaces)
            } else if kind == "new" {
                NewConversationPreviewCard(leadBot: leadBot)
            } else {
                BotsWidgetCard(bots: bots, wide: wide, large: size == "large")
            }
        }
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("%@尺寸小组件预览", size == "small" ? L("小") : size == "large" ? L("大") : L("中")))
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.caption.weight(.medium)).foregroundStyle(Palette.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func setupRow(_ title: String, complete: Bool, status: String? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: complete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(complete ? Palette.added : Palette.tertiary)
                .font(.system(size: 15))
            Text(title).font(.footnote).foregroundStyle(complete ? Palette.secondary : Palette.text)
            Spacer()
        }
        .padding(14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(status ?? (complete ? L("已完成") : L("未完成")))
    }

    private func checkNotifications() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let allowed: Bool? = switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        case .denied: false
        default: nil
        }
        withAnimation(Motion.reduced(Motion.layout, reduceMotion)) { notificationsAllowed = allowed }
    }

    /// Asks once; after a no, only the Settings app can turn them on.
    private func turnOnNotifications() {
        if notificationsAllowed == false {
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } else {
            Task {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                await checkNotifications()
            }
        }
    }

    private func checkWidgets() {
        let animation = Motion.reduced(Motion.layout, reduceMotion)
        withAnimation(animation) { widgetCheckFailed = false }
        WidgetCenter.shared.getCurrentConfigurations { result in
            let installed = (try? result.get())?.contains { $0.kind.hasPrefix("linGyU") }
            Task { @MainActor in
                withAnimation(animation) {
                    hasWidget = installed
                    widgetCheckFailed = installed == nil
                }
            }
        }
    }
}

// MARK: - Activity gallery

struct ActivityGalleryView: View {
    /// The presentations shown: the State tab splits Lock Screen from the Dynamic Island.
    var forms = BotActivityPreview.Form.allCases
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @AppStorage("cn.lingyu.liveActivitiesEnabled") private var enabled = true
    @State private var allowed = false
    @State private var form: BotActivityPreview.Form?
    @State private var phase = BotActivityPresentation.Phase.working
    @State private var startedAt = Date.now - 154

    private var island: Bool { !forms.contains(.lockScreen) }

    private var state: BotActivityPresentation {
        let status: String = switch phase {
        case .sending: "sending"
        case .queued: "queued"
        case .working, .stale: "working"
        case .needsInput: "needsInput"
        case .completed: "idle"
        case .failed: "error"
        case .waiting: "unknown"
        case .onCall: "onCall"
        }
        return .init(status: status, activity: phase == .needsInput ? L("看看提议的改动。") : L("正在跑测试。"),
                     isStale: phase == .stale)
    }

    /// The preview bot: a working one first, else the lead, else any bot.
    /// Nothing pre-made: with no bots the preview shows an honest empty state.
    private var previewBot: Bot? {
        store.connector.mirror.workingBots.first ?? store.connector.mirror.leadBot ?? store.connector.mirror.bots.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $enabled) {
                        Text(island ? L("在灵动岛中显示") : L("显示实时活动"))
                    }
                    .toggleStyle(.codync)
                    .font(.subheadline.weight(.medium))
                    Text(L("锁屏上的实时活动和灵动岛里的是一起开关的。"))
                        .font(.footnote).foregroundStyle(Palette.secondary)
                    Text(L("你从这部手机发任务或打电话给智能体时开始。看它的进度，智能体需要你时再打开对话。"))
                        .font(.footnote).foregroundStyle(Palette.secondary)
                    if !allowed {
                        Text(L("实时活动已在 iOS 设置里关掉了。"))
                            .font(.footnote).foregroundStyle(Palette.secondary)
                        Button(L("打开 iOS 设置")) { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                            .buttonStyle(.plain)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Palette.accent)
                    }
                }
                .padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(L("预览")).font(.subheadline.weight(.medium))
                        Spacer()
                        Text(L("示例任务")).font(.caption).foregroundStyle(Palette.secondary)
                    }
                    if forms.count > 1 {
                        ChoicePicker(selection: Binding(get: { form ?? forms[0] }, set: { form = $0 }),
                                     options: forms.map { ($0, $0.title) })
                    }
                    ChoicePicker(selection: $phase, options: [
                        (.sending, L("发送中")), (.queued, L("等待电脑")),
                        (.working, L("进行中")), (.needsInput, L("需要你确认")), (.completed, L("已完成")),
                        (.failed, L("出错")), (.stale, L("更新延迟")),
                    ])
                    if let bot = previewBot {
                        BotActivityPreview(bot: bot, state: state, form: form ?? forms[0], startedAt: startedAt)
                            .frame(maxWidth: .infinity, minHeight: 90)
                            .padding(12)
                            .background(Palette.bubbleAgent, in: RoundedRectangle(cornerRadius: 28))
                    } else {
                        Text(L("还没有智能体，预览等你新建一个智能体后才有。"))
                            .font(.subheadline).foregroundStyle(Palette.secondary)
                            .frame(maxWidth: .infinity, minHeight: 90)
                            .padding(12)
                            .background(Palette.bubbleAgent, in: RoundedRectangle(cornerRadius: 28))
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(forms, id: \.self) { explanation($0) }
                }
                Text(L("iOS 会根据你的设备和其他正在进行的任务来决定显示方式。这些预览不会真的启动一个实时活动。审批在 linGyU 里面处理。"))
                    .font(.footnote).foregroundStyle(Palette.secondary)
            }
            .padding(18).frame(maxWidth: 560).frame(maxWidth: .infinity)
        .background(Palette.background)
        .tint(Palette.accent)
        .task { await refreshAllowed() }
        .onChange(of: scenePhase) { _, value in
            if value == .active { Task { await refreshAllowed() } }
        }
    }

    private func refreshAllowed() async {
        allowed = ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private func explanation(_ form: BotActivityPreview.Form) -> some View {
        let detail = switch form {
        case .lockScreen: L("智能体的心情小人、当前步骤（按状态着色）、已跑时间、一个思考圆点和进度。智能体需要你时，点查看打开那个请求。")
        case .compact: L("摄像头旁边是智能体和一个思考圆点，外圈按状态着色。任务结束时圆点变成对勾或警告。")
        case .minimal: L("iOS 同时显示多个实时活动时，只剩一个圆点。")
        case .expanded: L("长按灵动岛看当前步骤和已跑时间，需要你时点查看。点一下打开对话。")
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(form.title).font(.subheadline.weight(.medium)).accessibilityAddTraits(.isHeader)
            Text(detail).font(.footnote).foregroundStyle(Palette.secondary)
        }
    }
}

struct LockWidgetGalleryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var kind = "bots"

    private var bots: [Bot] { store.connector.mirror.bots }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ChoicePicker(selection: $kind, options: [("bots", L("智能体")), ("usage", L("用量上限"))])
                Text(L("示例数据")).font(.caption).foregroundStyle(Palette.secondary)
                ForEach(AccessoryWidgetCard.Family.allCases, id: \.self) { family in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(familyTitle(family)).font(.subheadline.weight(.medium))
                        AccessoryWidgetCard(kind: kind == "bots" ? .bots : .usage, family: family,
                                            bots: bots, paired: store.connector.isPaired)
                            .frame(width: family == .circular ? 64 : family == .rectangular ? 160 : nil,
                                   height: family == .inline ? 24 : 64)
                            .padding(16).foregroundStyle(.white)
                            .background(.black, in: RoundedRectangle(cornerRadius: 20))
                            .environment(\.colorScheme, .dark)
                    }
                }
                Text(L("长按锁屏 → 自定 → 锁屏。点小组件区域，选 linGyU。行内小组件放在时钟上方的日期行里。"))
                    .font(.footnote).foregroundStyle(Palette.secondary)
                Text(L("选智能体看任务状态，选用量上限看上报的最高限额。iOS 会套用你锁屏的颜色和样式。"))
                    .font(.footnote).foregroundStyle(Palette.secondary)
            }
            .padding(18).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(Palette.background)
        .navigationTitle(L("锁屏小组件"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func familyTitle(_ family: AccessoryWidgetCard.Family) -> String {
        switch family {
        case .circular: return L("圆形")
        case .rectangular: return L("矩形")
        case .inline: return L("行内")
        }
    }
}

// MARK: - Widget setup demo

extension EnvironmentValues {
    /// False while the State tab or its Widget page is hidden, so the demo stops drawing.
    @Entry var stateSurfaceActive = true
}

/// "Add a widget", acted out on a drawn iPhone: hold the Home Screen,
/// Edit, Add Widget, find linGyU, add it, Done. Every frame is a pure
/// function of one clock, so it loops, pauses and scrubs.
struct WidgetSetupDemo: View {
    let bots: [Bot]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stateSurfaceActive) private var active
    @State private var playing = true
    /// The clock reads `base` at `since`, then runs on while playing.
    @State private var base: Double = 0
    @State private var since = Date.now
    @State private var scrubbing = false

    static let duration: Double = 9.5

    var body: some View {
        let running = playing && !scrubbing && active
        VStack(spacing: 14) {
            TimelineView(.animation(paused: !running)) { context in
                let t = time(at: context.date)
                VStack(spacing: 14) {
                    DemoPhone(bots: bots, t: t)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L("怎么添加 linGyU 小组件"))
                        .accessibilityValue(Self.step(at: t).text)
                    Text(Self.step(at: t).text)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Palette.text)
                        .contentTransition(.opacity)
                        .animation(Motion.fade, value: Self.step(at: t).index)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                    controls(t)
                }
            }
        }
        .onAppear { if reduceMotion { pause(at: 7.8) } }
        // Hidden tabs keep their place: the clock stops with them and picks up where it was.
        .onChange(of: active) { _, on in
            if on {
                since = .now
            } else if playing, !scrubbing {
                base = (base + Date.now.timeIntervalSince(since)).truncatingRemainder(dividingBy: Self.duration)
            }
        }
    }

    // MARK: clock

    private func time(at date: Date) -> Double {
        guard playing, !scrubbing, active else { return base }
        return (base + date.timeIntervalSince(since)).truncatingRemainder(dividingBy: Self.duration)
    }

    private func pause(at t: Double) {
        base = t
        playing = false
    }

    private func controls(_ t: Double) -> some View {
        HStack(spacing: 10) {
            Button {
                if playing {
                    pause(at: t)
                } else {
                    base = t
                    since = .now
                    playing = true
                }
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.iconButton)
            .accessibilityLabel(playing ? L("暂停") : L("播放"))
            GeometryReader { geo in
                let x = geo.size.width * t / Self.duration
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.accentDim).frame(height: 4)
                    Capsule().fill(Palette.accent).frame(width: x, height: 4)
                    Circle().fill(Palette.accent)
                        .frame(width: scrubbing ? 18 : 14, height: scrubbing ? 18 : 14)
                        .offset(x: x - (scrubbing ? 9 : 7))
                        .animation(Motion.press, value: scrubbing)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            scrubbing = true
                            base = min(max(value.location.x / geo.size.width, 0), 0.999) * Self.duration
                        }
                        .onEnded { _ in
                            since = .now
                            scrubbing = false
                        }
                )
            }
            .frame(height: 32)
            .accessibilityElement()
            .accessibilityLabel(L("步骤"))
            .accessibilityValue(Self.step(at: t).text)
            .accessibilityAdjustableAction { direction in
                let i = Self.step(at: t).index + (direction == .increment ? 1 : -1)
                guard Self.steps.indices.contains(i) else { return }
                pause(at: Self.steps[i].start + 0.05)
            }
        }
    }

    // MARK: script

    struct Step {
        let index: Int
        let start: Double
        let text: String
    }

    static let steps: [Step] = [
        Step(index: 0, start: 0, text: L("长按主屏幕上的空白处")),
        Step(index: 1, start: 1.8, text: L("点编辑，再点添加小组件")),
        Step(index: 2, start: 3.0, text: L("在列表里找到 linGyU")),
        Step(index: 3, start: 4.5, text: L("点添加小组件")),
        Step(index: 4, start: 6.0, text: L("点完成")),
    ]

    static func step(at t: Double) -> Step { steps.last { t >= $0.start } ?? steps[0] }
}

// MARK: - The phone

/// 0 before `a`, 1 after `b`, smooth in between.
private func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double {
    let x = min(max((t - a) / (b - a), 0), 1)
    return x * x * (3 - 2 * x)
}

/// Ease-out for things that arrive (sheets, pages).
private func arrive(_ t: Double, _ a: Double, _ b: Double) -> Double {
    let x = min(max((t - a) / (b - a), 0), 1)
    return 1 - pow(1 - x, 3)
}

private struct DemoPhone: View {
    let bots: [Bot]
    let t: Double

    private static let size = CGSize(width: 184, height: 384)
    private static let widgetHeight: CGFloat = 84

    // Where the finger goes and when it taps (screen points).
    private static let path: [(t: Double, p: CGPoint)] = [
        (0.2, CGPoint(x: 150, y: 300)), (0.9, CGPoint(x: 128, y: 262)), (1.8, CGPoint(x: 128, y: 262)),
        (2.2, CGPoint(x: 28, y: 40)), (2.45, CGPoint(x: 28, y: 40)), (2.8, CGPoint(x: 52, y: 66)),
        (3.1, CGPoint(x: 52, y: 66)), (3.9, CGPoint(x: 92, y: 177)), (4.5, CGPoint(x: 92, y: 177)),
        (5.1, CGPoint(x: 92, y: 334)), (6.2, CGPoint(x: 92, y: 334)), (6.8, CGPoint(x: 156, y: 40)),
        (7.6, CGPoint(x: 156, y: 40)),
    ]
    private static let taps: [Double] = [2.35, 2.95, 4.3, 5.75, 7.2]

    private var jiggle: Double { ramp(t, 1.45, 1.65) * (1 - ramp(t, 7.2, 7.35)) }
    private var menu: Double { ramp(t, 2.4, 2.55) * (1 - ramp(t, 2.95, 3.1)) }
    private var sheet: Double { arrive(t, 3.0, 3.5) * (1 - ramp(t, 5.8, 6.2)) }
    private var detail: Double { arrive(t, 4.4, 4.85) }
    private var placed: Double { arrive(t, 5.95, 6.4) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            wallpaper
            homeScreen
            editButtons
            editMenu
            gallery
            finger
            statusBar
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .padding(5)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 35, style: .continuous))
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity)
    }

    private var wallpaper: some View {
        LinearGradient(colors: [Color(red: 0.16, green: 0.33, blue: 0.43), Color(red: 0.29, green: 0.53, blue: 0.47)],
                       startPoint: .top, endPoint: .bottom)
            // The Home Screen dims behind the widget gallery.
            .overlay(Color.black.opacity(0.35 * sheet))
    }

    private var statusBar: some View {
        ZStack {
            Capsule().fill(.black).frame(width: 54, height: 16)
            HStack {
                Text("9:41").font(.system(size: 9, weight: .semibold))
                Spacer()
                Image(systemName: "battery.75percent").font(.system(size: 9))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
        }
        .frame(width: Self.size.width, height: 30)
    }

    // MARK: home

    private static let apps: [(String, Color)] = [
        ("message.fill", .green), ("calendar", .red), ("photo.fill", .orange), ("camera.fill", .gray),
        ("map.fill", .teal), ("clock.fill", .black), ("cloud.sun.fill", .blue), ("note.text", .yellow),
        ("music.note", .pink), ("book.fill", .orange), ("heart.fill", .red), ("gearshape.fill", .gray),
    ]
    private static let dock: [(String, Color)] = [("phone.fill", .green), ("safari.fill", .blue), ("envelope.fill", .blue), ("music.note", .red)]

    private var homeScreen: some View {
        VStack(spacing: 0) {
            BotsWidgetCard(bots: bots, wide: true)
                .padding(12)
                .frame(width: 164 / 0.62, height: Self.widgetHeight / 0.62)
                .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 22 / 0.62, style: .continuous))
                .scaleEffect(0.62)
                .frame(width: 164, height: Self.widgetHeight)
                .scaleEffect(0.9 + 0.1 * placed, anchor: .top)
                .rotationEffect(.degrees(jiggle * 1.2 * sin(t * 30 + 5)))
                .opacity(placed)
                // The icons below slide down as the widget takes its row.
                .frame(height: (Self.widgetHeight + 14) * placed, alignment: .top)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 10), count: 4), spacing: 12) {
                ForEach(Self.apps.indices, id: \.self) { i in
                    icon(Self.apps[i], index: i)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                ForEach(Self.dock.indices, id: \.self) { i in icon(Self.dock[i], index: i + 20, label: false) }
            }
            .padding(9)
            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.bottom, 8)
        }
        .padding(.top, 58)
        .frame(width: Self.size.width, height: Self.size.height)
        .scaleEffect(1 - 0.04 * sheet)
    }

    private func icon(_ app: (String, Color), index: Int, label: Bool = true) -> some View {
        VStack(spacing: 3) {
            Image(systemName: app.0)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(app.1.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            if label { Capsule().fill(.white.opacity(0.55)).frame(width: 20, height: 3) }
        }
        .rotationEffect(.degrees(jiggle * 2.4 * sin(t * 32 + Double(index) * 1.7)))
    }

    // MARK: edit mode

    private var editButtons: some View {
        HStack {
            pill(L("编辑"), highlighted: pressed(near: 2.35))
            Spacer()
            pill(L("完成"), highlighted: pressed(near: 7.2))
        }
        .padding(.horizontal, 12)
        .padding(.top, 30)
        .frame(width: Self.size.width)
        .opacity(jiggle)
    }

    private func pill(_ title: String, highlighted: Bool) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background(.white.opacity(highlighted ? 0.45 : 0.25), in: Capsule())
    }

    private var editMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuRow(L("添加小组件"), "plus.rectangle.on.rectangle", highlighted: pressed(near: 2.95))
            Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5)
            menuRow(L("自定"), "paintbrush", highlighted: false)
        }
        .frame(width: 104)
        .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(0.6 + 0.4 * menu, anchor: .topLeading)
        .opacity(menu)
        .offset(x: 12, y: 54)
    }

    private func menuRow(_ title: String, _ symbol: String, highlighted: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 9, weight: .medium))
            Spacer(minLength: 0)
            Image(systemName: symbol).font(.system(size: 9))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(.white.opacity(highlighted ? 0.12 : 0))
    }

    // MARK: widget gallery

    private var gallery: some View {
        ZStack(alignment: .topLeading) {
            galleryList
                .offset(x: -40 * detail)
                .opacity(1 - detail)
            galleryDetail
                .offset(x: Self.size.width * (1 - detail))
        }
        .frame(width: Self.size.width, height: Self.size.height - 60, alignment: .top)
        .background(Color(white: 0.12), in: UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20, style: .continuous))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20, style: .continuous))
        .offset(y: 60 + (Self.size.height - 60) * (1 - sheet))
    }

    private var galleryList: some View {
        VStack(spacing: 0) {
            Capsule().fill(.white.opacity(0.3)).frame(width: 28, height: 3).padding(.vertical, 6)
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                Text(L("搜索小组件"))
                Spacer()
            }
            .font(.system(size: 9))
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(.white.opacity(0.1), in: Capsule())
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            listRow(L("电池"), Image(systemName: "battery.100percent"), tint: .green)
            listRow(L("日历"), Image(systemName: "calendar"), tint: .red)
            listRow("linGyU", nil, tint: .clear, highlighted: pressed(near: 4.3))
            listRow(L("健身"), Image(systemName: "figure.run"), tint: .orange)
            listRow(L("天气"), Image(systemName: "cloud.sun.fill"), tint: .blue)
        }
    }

    private func listRow(_ title: String, _ symbol: Image?, tint: Color, highlighted: Bool = false) -> some View {
        HStack(spacing: 8) {
            Group {
                if let symbol {
                    symbol.font(.system(size: 10)).foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(tint.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else {
                    CharacterAvatar(shape: "hex", color: "gray", size: 20)
                }
            }
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.white)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 7, weight: .semibold)).foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(.white.opacity(highlighted ? 0.1 : 0))
    }

    private var galleryDetail: some View {
        VStack(spacing: 12) {
            Capsule().fill(.white.opacity(0.3)).frame(width: 28, height: 3).padding(.top, 6)
            HStack(spacing: 6) {
                CharacterAvatar(shape: "hex", color: "gray", size: 18)
                Text("linGyU").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            }
            Text(L("看谁需要你、谁还在干活。"))
                .font(.system(size: 8)).foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            BotsWidgetCard(bots: bots, wide: true)
                .padding(12)
                .frame(width: 164 / 0.62, height: Self.widgetHeight / 0.62)
                .background(Color(white: 0.2), in: RoundedRectangle(cornerRadius: 22 / 0.62, style: .continuous))
                .scaleEffect(0.62)
                .frame(width: 164, height: Self.widgetHeight)
                .padding(.top, 8)
            HStack(spacing: 4) {
                ForEach(0..<3) { i in Circle().fill(.white.opacity(i == 1 ? 0.9 : 0.3)).frame(width: 4, height: 4) }
            }
            Spacer()
            Label(L("添加小组件"), systemImage: "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 140, height: 28)
                .background(.white.opacity(pressed(near: 5.75) ? 0.75 : 1), in: Capsule())
                .scaleEffect(pressed(near: 5.75) ? 0.96 : 1)
                .padding(.bottom, 26)
        }
        .frame(width: Self.size.width)
    }

    // MARK: finger

    private func pressed(near tap: Double) -> Bool { abs(t - tap) < 0.12 }

    private var fingerPoint: CGPoint {
        let path = Self.path
        guard let next = path.firstIndex(where: { $0.t > t }) else { return path.last!.p }
        guard next > 0 else { return path[0].p }
        let a = path[next - 1], b = path[next]
        let k = ramp(t, a.t, b.t)
        return CGPoint(x: a.p.x + (b.p.x - a.p.x) * k, y: a.p.y + (b.p.y - a.p.y) * k)
    }

    private var finger: some View {
        let visible = ramp(t, 0.15, 0.4) * (1 - ramp(t, 7.5, 7.8))
        let tapDepth = Self.taps.map { max(0, 1 - abs(t - $0) / 0.14) }.max() ?? 0
        let holding = ramp(t, 0.95, 1.05) * (1 - ramp(t, 1.65, 1.75))
        let hold = ramp(t, 1.0, 1.6)
        let p = fingerPoint
        return ZStack {
            // The long press fills a ring before edit mode starts.
            Circle().trim(from: 0, to: hold * holding)
                .stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 34, height: 34)
            Circle().fill(.white.opacity(0.35 + 0.25 * max(tapDepth, holding)))
                .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1.5))
                .frame(width: 24, height: 24)
                .scaleEffect(1 - 0.2 * max(tapDepth, holding))
        }
        .opacity(visible)
        .position(p)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }
}
