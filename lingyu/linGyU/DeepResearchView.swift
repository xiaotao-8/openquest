import SwiftUI

/// 深度研究: the user asks for a researched, sourced report. The request
/// is drafted to the lead agent in chat (the research itself runs on the
/// computer); results come back in chat and can be saved to the Feed.
struct DeepResearchView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var topic = ""

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: L("深度研究"), trailing: AnyView(
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.iconButton)
                .accessibilityLabel(L("关闭"))
            ))
            VStack(alignment: .leading, spacing: 12) {
                Text(L("让智能体就一个问题查资料、对比来源，给你一份结构化报告。"))
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
                TextField(L("要研究什么？"), text: $topic, axis: .vertical)
                    .font(.body)
                    .lineLimit(3...6)
                    .padding(12)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                Button {
                    let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.draftToLeadBot(L("请就「%@」做一份深度研究：查资料、对比来源，给我一份结构化报告。", trimmed))
                    dismiss()
                } label: {
                    Text(L("开始研究"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .disabled(topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.leadBot == nil)
                if store.leadBot == nil {
                    Text(L("需要先配对电脑并有智能体。"))
                        .font(.footnote)
                        .foregroundStyle(Palette.secondary)
                }
                Text(L("研究在电脑端进行，结果回到聊天里，写好的报告可以保存到简报。"))
                    .font(.footnote)
                    .foregroundStyle(Palette.secondary)
            }
            .padding(18)
            Spacer()
        }
        .background(Palette.background)
    }
}
