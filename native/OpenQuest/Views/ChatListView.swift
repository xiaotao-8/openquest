import SwiftUI

/// 聊天列表：群和单聊混排。头像（首字圆盘）+ 名字 + 最后一句 + 时间；
/// 有智能体在干活时，状态写在该行下面。纯黑底，原生列表。
struct ChatListView: View {
    @EnvironmentObject var store: AppStore
    @State private var showingNewChat = false

    var body: some View {
        Group {
            if store.conversations.isEmpty {
                ContentUnavailableView(
                    "还没有聊天",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("点右上角新建：先建智能体，再拉群或单聊。")
                )
            } else {
                List {
                    ForEach(store.conversations) { conv in
                        NavigationLink(value: conv.id) {
                            ConversationRow(conversation: conv)
                        }
                    }
                    .onDelete { idx in
                        for i in idx { store.deleteConversation(id: store.conversations[i].id) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color.black)
        .navigationTitle("聊天")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingNewChat = true } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $showingNewChat) { NewChatView() }
    }
}

private struct ConversationRow: View {
    @EnvironmentObject var store: AppStore
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            AvatarDisc(text: String(conversation.title.prefix(1)),
                      hue: 0.6, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(conversation.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(conversation.lastActivity, format: .dateTime.hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(conversation.lastPreview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let note = conversation.workingNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// 首字圆盘头像：不用 emoji、不用 App 图标。
struct AvatarDisc: View {
    let text: String
    let hue: Double
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color(hue: hue, saturation: 0.45, brightness: 0.55))
            .frame(width: size, height: size)
            .overlay {
                Text(text)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}
