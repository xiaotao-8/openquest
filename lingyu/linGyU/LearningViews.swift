import SwiftUI

/// The learning proposal card (FishPocket `learning-answer`, Phase 4,
/// agent F): a skill the bot taught itself, or a change to the folder's
/// AGENTS.md. The preview is at most 220pt tall and scrolls.
///
/// Host gap (probe 2026-11-22): codync-host 2.51.0 has no
/// `learning-answer` — it answers 404 "unknown method" — so Approve /
/// Reject are disabled states with a reason (§1.6.4). Nothing here
/// sends anything to the host.
struct LearningCard: View {
    var entry: Entry
    var bot: Bot

    private var proposal: LearningProposal? { entry.data.learning }
    private var isPending: Bool { entry.data.status == "pending" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let proposal {
                HStack(spacing: 8) {
                    Text(L("学习提案"))
                        .font(.headline)
                        .foregroundStyle(Palette.text)
                    Text(proposal.isAgentsChange ? L("修改建议") : L("新技能"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Spacer()
                }
                if !proposal.title.isEmpty {
                    Text(proposal.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Palette.text)
                }
                if let summary = proposal.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                }
                if let target = proposal.target, !target.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: proposal.isAgentsChange ? "doc.text" : "square.stack")
                            .font(.caption)
                            .foregroundStyle(Palette.tertiary)
                        Text(target)
                            .font(.caption.monospaced())
                            .foregroundStyle(Palette.tertiary)
                            .lineLimit(1)
                    }
                }
                if !proposal.previewText.isEmpty {
                    ScrollView(showsIndicators: false) {
                        Text(proposal.previewText)
                            .font(.caption.monospaced())
                            .foregroundStyle(Palette.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 220)
                    .padding(8)
                    .background(Palette.codeBackground, in: RoundedRectangle(cornerRadius: 8))
                }
                if isPending {
                    HStack(spacing: 10) {
                        Text(L("批准"))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.onAccent)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Palette.accentFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .opacity(0.4)
                        Text(L("拒绝"))
                            .font(.body)
                            .foregroundStyle(Palette.text)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .opacity(0.4)
                    }
                    .disabled(true)
                    DisabledReasonLine(text: L("电脑暂不支持学习提案"))
                } else {
                    Text(outcomeText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.secondary)
                }
            } else {
                Text(L("提案内容无法显示。"))
                    .font(.body)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Palette.bubbleAgent, in: RoundedRectangle(cornerRadius: 22))
        .padding(.trailing, 40)
    }

    private var outcomeText: String {
        switch entry.data.status {
        case "answered":
            return entry.data.selected ?? L("已回答")
        case "cancelled":
            return L("已取消")
        default:
            return L("已回答")
        }
    }
}
