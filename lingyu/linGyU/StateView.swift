import SwiftUI

/// State (§1.1): Widget / Live Activity / Dynamic Island segments + three
/// galleries + Usage entry. The pending-approvals block stays (a fusion
/// addition): it is the ApprovalSheet's entry point.
struct StateView: View {
    @EnvironmentObject private var store: AppStore
    @State private var segment = 0
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
            SegmentedChoice(selection: $segment, options: segments.enumerated().map { (value: $0.offset, title: $0.element) })
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
                Button(action: dismiss) {
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
