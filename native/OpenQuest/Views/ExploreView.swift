import SwiftUI

/// 探索页（FishPocket 探索 Tab 同款位置）：插件商店、定时任务、技能、小工具。
/// 云电脑是内置的（服务器直连写死在 App 里），不单独显示入口页。
struct ExploreView: View {
    @EnvironmentObject var store: AppStore

    private func L(_ key: String) -> String { L10n.t(key, lang: store.language) }

    var body: some View {
        NavigationStack {
            List {
                Section(L("discover")) {
                    NavigationLink { PluginStoreView() } label: {
                        ExploreRow(icon: "puzzlepiece",
                                   title: L("plugins"), subtitle: L("plugins_subtitle"))
                    }
                    NavigationLink { SchedulesView() } label: {
                        ExploreRow(icon: "alarm",
                                   title: L("schedules"),
                                   value: store.scheduledTasks.isEmpty
                                       ? nil : "\(store.scheduledTasks.count)")
                    }
                    NavigationLink { SkillsView() } label: {
                        ExploreRow(icon: "wand.and.stars",
                                   title: L("skills"),
                                   value: store.skills.isEmpty ? nil : "\(store.skills.count)")
                    }
                    NavigationLink { MiniAppsView() } label: {
                        ExploreRow(icon: "square.on.circle",
                                   title: L("mini_apps"),
                                   value: store.miniApps.isEmpty ? nil : "\(store.miniApps.count)")
                    }
                }
            }
            .navigationTitle(L("explore"))
        }
    }
}

private struct ExploreRow: View {
    let icon: String
    var title: String
    var subtitle: String? = nil
    var value: String? = nil

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Palette.ink)
                .frame(width: 29, height: 29)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let value {
                Text(value).foregroundStyle(.secondary)
            }
        }
    }
}
