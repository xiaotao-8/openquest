import SwiftUI

/// Soul 页（Minis `SOUL.md`，Agent/Session/SoulStore.swift：
/// 用户亲笔的身份与规矩，进系统提示时排在最前面）。
/// 注意：这里存的只是用户自己写的 Soul 文本；写死在底层的提示词
/// （Soul 置顶 + 绑定框 + 每轮末尾规则 + 拒绝逼三轮）在 BakedPersona 里，
/// 这个文件一个字节都不动，两者是两回事。
struct SoulView: View {
    @EnvironmentObject var store: AppStore
    @State private var draft = ""
    @State private var savedNote: String?

    var body: some View {
        Form {
            Section {
                Text("这是最高优先级指令：你在这里写的每一句，智能体都要先于其他一切人设、技能和规则遵守。写你希望它一直记住的身份、风格和规矩。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Soul（SOUL.md）") {
                TextEditor(text: $draft)
                    .frame(minHeight: 280)
                    .autocorrectionDisabled()
                HStack {
                    Text("\(draft.count) 字").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let savedNote {
                        Text(savedNote).font(.caption).foregroundStyle(.green)
                    }
                }
            }
            Section {
                Button("保存 Soul") {
                    store.setSoulText(draft)
                    savedNote = "已保存"
                }
                .disabled(draft == store.soulText)
                Text("保存后立刻生效：之后每轮对话，Soul 都拼在系统提示的最前面。清空并保存就是不用 Soul。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Soul")
        .onAppear { draft = store.soulText }
    }
}
