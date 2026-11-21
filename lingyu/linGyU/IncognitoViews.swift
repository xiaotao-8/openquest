import SwiftUI

/// 新建私密会话: pick an agent to chat with incognito. A private session
/// leaves nothing on this phone — no draft, no local copy — but the
/// content still goes through the computer that runs the agent.
struct IncognitoBotPicker: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: L("新建私密会话"), trailing: AnyView(
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.iconButton)
                .accessibilityLabel(L("关闭"))
            ))
            Text(L("私密会话不在本机留存草稿和记录，内容仍经过电脑端处理。"))
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            List {
                ForEach(store.connector.mirror.bots.filter { !$0.isGroup }) { bot in
                    Button {
                        store.openIncognitoChat(botId: bot.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            BotAvatar(bot: bot, size: 36)
                            Text(bot.name)
                                .font(.body)
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
            .listStyle(.insetGrouped)
        }
        .background(Palette.background)
    }
}
