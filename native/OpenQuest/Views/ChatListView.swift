import SwiftUI

/// 聊天列表：群和单聊混排。自定义行（没有系统列表的箭头），
/// 头像颜色按智能体区分；空的时候是专门设计的空状态，不是白板。
struct ChatListView: View {
    @EnvironmentObject var store: AppStore
    @Binding var path: [UUID]
    @State private var showingNewChat = false
    @State private var searchText = ""

    private var filtered: [Conversation] {
        if searchText.isEmpty { return store.conversations }
        return store.conversations.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if store.conversations.isEmpty {
                EmptyHomeView { showingNewChat = true }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { conv in
                            Button { path.append(conv.id) } label: {
                                ConversationRow(conversation: conv)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.deleteConversation(id: conv.id)
                                } label: {
                                    Label("删除会话", systemImage: "trash")
                                }
                            }
                            Divider().padding(.leading, 76)
                        }
                    }
                }
            }
        }
        .background(Color.black)
        .navigationTitle("聊天")
        .searchable(text: $searchText, prompt: "搜索")
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

/// 空状态：什么都不预置，但空得有设计——玻璃圆钮 + 一句引导 + 大按钮。
private struct EmptyHomeView: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 34))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .glassEffect(.regular, in: Circle())
            Text("还没有聊天")
                .font(.title3.weight(.semibold))
            Text("先建一个智能体，给它选好模型，\n再拉它单聊或者组个群。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onCreate) {
                Label("新建", systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 22).padding(.vertical, 11)
            }
            .glassEffect(.regular.interactive(), in: Capsule())
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }
}

private struct ConversationRow: View {
    @EnvironmentObject var store: AppStore
    let conversation: Conversation

    /// 头像：单聊用那个智能体的颜色和首字；群用群名首字、取第一个成员的颜色。
    private var avatar: (text: String, hue: Double) {
        if conversation.isGroup {
            let first = conversation.memberIds.first.flatMap { store.agent(id: $0) }
            return (String(conversation.title.prefix(1)), first?.tintHue ?? 0.62)
        }
        if let a = conversation.memberIds.first.flatMap({ store.agent(id: $0) }) {
            return (a.initial, a.tintHue)
        }
        return (String(conversation.title.prefix(1)), 0.62)
    }

    var body: some View {
        HStack(spacing: 12) {
            AvatarDisc(text: avatar.text, hue: avatar.hue, size: 50)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: firstTextBaseline) {
                    Text(conversation.title)
                        .font(.body.weight(.semibold))
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
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// 首字圆盘头像：不用 emoji、不用 App 图标。
struct AvatarDisc: View {
    let text: String
    let hue: Double
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color(hue: hue, saturation: 0.42, brightness: 0.58))
            .frame(width: size, height: size)
            .overlay {
                Text(text)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}
