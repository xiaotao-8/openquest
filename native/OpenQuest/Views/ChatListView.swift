import SwiftUI

/// 聊天列表：群和单聊混排。自定义行（没有系统列表的箭头），
/// 头像颜色按智能体区分；空的时候是专门设计的空状态，不是白板。
struct ChatListView: View {
    @EnvironmentObject var store: AppStore
    @Binding var path: [UUID]
    @State private var showingNewChat = false
    @State private var searchText = ""
    @State private var showingImport = false
    @State private var importStatus: String?

    private func L(_ key: String) -> String { L10n.t(key, lang: store.language) }

    private var filtered: [Conversation] {
        if searchText.isEmpty { return store.conversations }
        return store.conversations.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if store.conversations.isEmpty {
                EmptyHomeView(
                    onDirect: { path.append(store.ensureDirectChat()) },
                    onCreate: { showingNewChat = true }
                )
            } else {
                VStack(spacing: 0) {
                    if !store.conversations.contains(where: { $0.title == "直接聊" }) {
                        Button {
                            path.append(store.ensureDirectChat())
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(.system(size: 20))
                                    .frame(width: 50, height: 50)
                                    .liquidGlass(Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L("direct_chat")).font(.body.weight(.semibold))
                                    Text(L("direct_hint"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 78)
                    }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField(L("search"), text: $searchText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .liquidGlass(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 6)
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
                        Color.clear.frame(height: 96)
                    }
                }
                }
            }
        }
        .background(Color.black)
        .navigationTitle(L("nav_chat"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingNewChat = true } label: {
                        Label(L("new_chat"), systemImage: "square.and.pencil")
                    }
                    Button { showingImport = true } label: {
                        Label("导入会话（DeepSeek / Chatbox）", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $showingNewChat) { NewChatView() }
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                importStatus = "文件读不出来"
                return
            }
            let sessions = ChatImport.parse(data)
            if sessions.isEmpty {
                importStatus = "没认出这是 DeepSeek 或 Chatbox 导出的会话"
                return
            }
            let n = ChatImport.importInto(store, sessions: sessions)
            importStatus = "导入了 \(n) 个会话"
        }
        .alert("导入会话", isPresented: Binding(
            get: { importStatus != nil },
            set: { if !$0 { importStatus = nil } }
        )) {
            Button("好") { importStatus = nil }
        } message: {
            Text(importStatus ?? "")
        }
    }
}

/// 空状态：打开就能直接聊，不用先建智能体；想组队再去建。
private struct EmptyHomeView: View {
    @EnvironmentObject var store: AppStore
    let onDirect: () -> Void
    let onCreate: () -> Void

    private func L(_ key: String) -> String { L10n.t(key, lang: store.language) }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 34))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .liquidGlass(Circle())
            Text(L("empty_title"))
                .font(.title3.weight(.semibold))
            Text(L("empty_hint"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onDirect) {
                Label(L("direct_chat"), systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 26).padding(.vertical, 12)
            }
            .liquidGlassInteractive(Capsule())
            Button(L("new_chat"), action: onCreate)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                HStack(alignment: .firstTextBaseline) {
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
                        .foregroundStyle(.green)
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
