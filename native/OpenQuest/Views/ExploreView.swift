import SwiftUI

/// 探索页（FishPocket 探索 Tab 同款位置）：云电脑入口 + 插件商店、定时任务、技能、小工具。
struct ExploreView: View {
    @EnvironmentObject var store: AppStore

    private func L(_ key: String) -> String { L10n.t(key, lang: store.language) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { CloudComputerView() } label: {
                        ExploreRow(icon: "server.rack",
                                   title: L("cloud_computer"),
                                   subtitle: "ECS 常驻主机：终端、文件、服务器浏览器")
                    }
                }
                Section("发现") {
                    NavigationLink { PluginStoreView() } label: {
                        ExploreRow(icon: "puzzlepiece",
                                   title: L("plugins"), subtitle: "在 App 内安装、配置和使用")
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
