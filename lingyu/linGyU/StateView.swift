import SwiftUI

/// State (§1.1): Widget / Live Activity / Dynamic Island segments + preview
/// + Usage entry. The Muse lower half (Activity / Approvals / Upcoming) is
/// Phase 2; Phase 1 shows pending approvals here so the ApprovalSheet has a
/// real entry point.
struct StateView: View {
    @EnvironmentObject private var store: AppStore
    @State private var segment = 0
    @State private var showInDynamicIsland = true
    @State private var showingUsage = false
    @State private var showingApprovals = false

    private var segments: [String] {
        [L("小组件"), L("实时活动"), L("灵动岛")]
    }

    private var pendingEntries: [Entry] {
        store.connector.mirror.bots.flatMap { bot in
            store.connector.mirror.entries(for: bot.id).filter { $0.isWaitingCard }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ScreenHeader(title: L("状态"), trailing: AnyView(
                    Button {
                        showingUsage = true
                    } label: {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Palette.secondary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("用量"))
                ))
                TabChoice(titles: segments, selection: $segment)
                    .padding(.horizontal, 20)
                dynamicIslandPreview
                if !pendingEntries.isEmpty {
                    approvalsSection
                }
                usageRow
                formFactorNotes
            }
            .padding(.bottom, 24)
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
    }

    private var firstPendingBot: Bot? {
        guard let entry = pendingEntries.first else { return nil }
        return store.connector.mirror.bot(id: entry.botId)
    }

    private var dynamicIslandPreview: some View {
        VStack(spacing: 16) {
            CardSection(title: L("灵动岛")) {
                CardRow {
                    Toggle(L("在灵动岛中显示"), isOn: $showInDynamicIsland)
                        .toggleStyle(.codync)
                }
            }
            // Black Dynamic Island preview: avatar + thinking orb.
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.black)
                    .frame(width: 220, height: 48)
                HStack(spacing: 8) {
                    if let bot = store.connector.mirror.workingBots.first ?? store.connector.mirror.leadBot {
                        AvatarView(bot: bot, size: 28)
                        Circle()
                            .fill(Palette.secondary)
                            .frame(width: 12, height: 12)
                        Text(bot.activity.isEmpty ? L("工作中…") : bot.activity)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    } else {
                        Text(L("没有进行中的工作"))
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 20)
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
        .padding(.horizontal, 20)
    }

    private var usageRow: some View {
        CardSection(title: L("用量")) {
            CardRow {
                Button {
                    showingUsage = true
                } label: {
                    HStack {
                        Text(L("用量"))
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
        .padding(.horizontal, 20)
    }

    private var formFactorNotes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(segmentDescription)
                .font(.body)
                .foregroundStyle(Palette.secondary)
        }
        .padding(.horizontal, 20)
    }

    private var segmentDescription: String {
        switch segment {
        case 0:
            return L("小组件把智能体的工作状态放到主屏幕：谁在干活、进度如何，一眼看到。")
        case 1:
            return L("实时活动在锁屏上显示正在进行的工作，完成后自动消失。")
        default:
            return L("灵动岛在通话、导航等场景下也能看到智能体的工作状态。")
        }
    }
}

/// The Usage sheet (S13): per-provider cards. Phase 1 shows the empty
/// state — the `usage` RPC is a Phase 2 item (§7.5).
struct UsageView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(L("用量"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.text)
                Spacer()
                Color.clear.frame(width: 36, height: 36)
            }
            .frame(height: 56)
            .padding(.horizontal, 12)
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
        .background(Palette.background)
    }
}
