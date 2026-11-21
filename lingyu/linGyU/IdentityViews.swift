import SwiftUI

// MARK: - Shared Markdown editor

/// A plain Markdown editor for the three identity files. The text is the
/// file's content; saving writes the file back.
struct MarkdownEditorView: View {
    @Binding var text: String
    var placeholder: String
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(Palette.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 10)
                }
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 2)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            Spacer()
            Button {
                onSave()
                dismiss()
            } label: {
                Text(L("保存"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent)
            .padding(18)
        }
        .background(Palette.background)
    }
}

// MARK: - Soul

/// Soul: the highest-priority instruction set. The agent follows it above
/// everything else. The file lives on this device (Documents/identity/
/// soul.md); nothing is pre-filled.
struct SoulView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Soul 是最高优先级的指令：人设、风格、规矩，智能体必须完全服从。"))
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
                if store.identity.soulChangedExternally {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("Soul 文件在别处被改过。"))
                                .font(.subheadline.weight(.semibold))
                            Text(L("保存会覆盖那次改动；也可以先看一眼再决定。"))
                                .font(.footnote)
                                .foregroundStyle(Palette.secondary)
                        }
                        Spacer()
                        Button(L("知道了")) {
                            store.identity.acknowledgeExternalSoulChange()
                        }
                        .buttonStyle(.plain)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                    }
                    .padding(12)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            MarkdownEditorView(
                text: $draft,
                placeholder: L("写下智能体必须服从的规矩…"),
                onSave: { store.identity.saveSoul(draft) }
            )
        }
        .onAppear { draft = store.identity.soul }
        .navigationTitle(L("Soul"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Memory

/// Memory: what the agent remembers about the user, as a Markdown file
/// (Documents/identity/memory.md). The user can read it, edit it, or
/// forget it entirely.
struct MemoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft = ""
    @State private var confirmForget = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("智能体记住的关于你的事。写在这里的才会被记住，不想留的随时删掉。"))
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
                Button {
                    confirmForget = true
                } label: {
                    Label(L("全部忘记"), systemImage: "trash")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .disabled(store.identity.memory.isEmpty && draft.isEmpty)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            MarkdownEditorView(
                text: $draft,
                placeholder: L("智能体应该记住的事…"),
                onSave: { store.identity.saveMemory(draft) }
            )
        }
        .onAppear { draft = store.identity.memory }
        .navigationTitle(L("Memory"))
        .navigationBarTitleDisplayMode(.inline)
        .codyncDialog(
            isPresented: $confirmForget,
            title: L("全部忘记？"),
            message: L("会清空整份记忆文件，这个操作无法撤销。"),
            actions: [
                CodyncDialogAction(title: L("取消")) {},
                CodyncDialogAction(title: L("全部忘记"), isDestructive: true) {
                    store.identity.forgetMemory()
                    draft = ""
                },
            ]
        )
    }
}

// MARK: - Identity

/// Identity: who the assistant is — name, vibe, tagline, and a longer
/// self-description (Documents/identity/identity.md). Changing the name
/// or avatar can also go through chat, the way the original does: it
/// drafts a message to the lead agent.
struct IdentityView: View {
    @EnvironmentObject private var store: AppStore
    @State private var name = ""
    @State private var vibe = ""
    @State private var tagline = ""
    @State private var body = ""
    @State private var showingAudit = false

    var body: some View {
        List {
            Section {
                LabeledField(label: L("名字"), text: $name, placeholder: L("智能体的名字"))
                LabeledField(label: L("风格"), text: $vibe, placeholder: L("比如：冷静、直接"))
                LabeledField(label: L("简介"), text: $tagline, placeholder: L("一句话介绍"))
            } header: {
                Text(L("身份"))
            } footer: {
                Text(L("名字、风格和简介写进 identity.md，智能体照此介绍自己。"))
            }
            Section {
                ZStack(alignment: .topLeading) {
                    if body.isEmpty {
                        Text(L("更长的自我介绍…"))
                            .font(.body)
                            .foregroundStyle(Palette.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                    }
                    TextEditor(text: $body)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 140)
                }
            } header: {
                Text(L("自我介绍"))
            }
            Section {
                Button {
                    store.draftToLeadBot(L("请把你的名字改成「%@」", name))
                } label: {
                    Label(L("在聊天里改名"), systemImage: "message")
                }
                .disabled(store.leadBot == nil)
                Button {
                    store.draftToLeadBot(L("请帮我换一个头像"))
                } label: {
                    Label(L("在聊天里换头像"), systemImage: "person.crop.circle")
                }
                .disabled(store.leadBot == nil)
                if store.leadBot == nil {
                    Text(L("需要先配对电脑并有智能体。"))
                        .font(.footnote)
                        .foregroundStyle(Palette.secondary)
                }
            } header: {
                Text(L("通过聊天改"))
            } footer: {
                Text(L("改名和换头像也可以在聊天里告诉智能体，它会起草改动给你确认。"))
            }
            Section {
                Button {
                    showingAudit = true
                } label: {
                    Label(L("审核记录"), systemImage: "list.clipboard")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("Identity"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("保存")) {
                    store.identity.saveIdentity(name: name, vibe: vibe, tagline: tagline, body: body)
                }
                .font(.headline)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          && vibe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          && tagline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .codyncSheet(isPresented: $showingAudit) {
            NavigationStack { AuditLogView() }
        }
        .onAppear {
            name = store.identity.identityName
            vibe = store.identity.identityVibe
            tagline = store.identity.identityTagline
            body = store.identity.identityBody
        }
    }
}

private struct LabeledField: View {
    var label: String
    @Binding var text: String
    var placeholder: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.body)
                .frame(width: 56, alignment: .leading)
                .foregroundStyle(Palette.secondary)
            TextField(placeholder, text: $text)
                .font(.body)
        }
    }
}
