import SwiftUI

/// 权限页（Minis Permissions 页移植）。
///
/// 源码出处：`~/workspace/reference/minis/src/ios/Views/Settings/OffloadPermissionSettingsView.swift`
/// （右上 "Set All Bypass" 胶囊；Privacy 行右侧蓝色 "Bypass"；Configuration Tool 分组里
/// "Allow minis-config" 总开关；说明文字：关了智能体就不能经 minis-config 读写任何设置，
/// 改动记录仍可在 Logs → Config Changes 里查）。
///
/// 本地落法：
/// - “全部跳过审批（Set All Bypass）”在顶部，是总开关，默认关；打开时先弹风险确认，
///   确认后才把逐项权限全置为“跳过审批”。关掉则全恢复为“每次询问”。
/// - 逐项权限行：每项三档——每次询问 / 跳过审批 / 禁止。
/// - 全部跳过审批只覆盖工具审批，不覆盖提问卡；敏感改动（启用连接器、授手机权限、定时自启）
///   永远走审批卡（MinisConfig.isSensitive），全部跳过审批也盖不住。
/// - minis-config 总开关也在本页（与 Minis 原版同位置），开关本身只能用户手动改。
///
/// 挂载点（给协调员）：SettingsView（RootView.swift）里加一行
/// `SettingRow(icon: "lock.shield.fill", color: .orange, title: "权限") { PermissionsView() }`。
/// 本文件不改 RootView.swift。
final class PermissionsStore: ObservableObject {
    static let shared = PermissionsStore()

    enum Level: String, CaseIterable, Codable {
        case ask = "ask"        // 每次询问
        case bypass = "bypass"  // 跳过审批
        case denied = "denied"  // 禁止

        var label: String {
            switch self {
            case .ask: return "每次询问"
            case .bypass: return "跳过审批"
            case .denied: return "禁止"
            }
        }
    }

    struct Item: Identifiable {
        let id: String
        let name: String
        let summary: String
    }

    /// 逐项权限 = 统一工具协议里的工具名，与 AgentTools 的工具名一一对应。
    static let items: [Item] = [
        Item(id: "run_server_command", name: "服务器命令", summary: "在云电脑上执行 shell 命令"),
        Item(id: "browse_on_server", name: "服务器浏览器", summary: "操作服务器上的真实浏览器"),
        Item(id: "fetch_webpage", name: "抓网页", summary: "按网址抓取页面正文"),
        Item(id: "spawn_subagent", name: "派活给其他智能体", summary: "把子任务派给另一个智能体"),
        Item(id: "device_calendar", name: "日历", summary: "在手机日历里新建日程"),
        Item(id: "device_reminder", name: "提醒事项", summary: "在手机提醒事项里新建提醒"),
        Item(id: "device_photos", name: "照片", summary: "读相册里最近照片的数量和时间"),
        Item(id: "device_clipboard", name: "剪贴板", summary: "读写剪贴板文字"),
        Item(id: "device_location", name: "位置", summary: "读一次当前位置"),
        Item(id: "device_contacts", name: "通讯录", summary: "按名字查联系人"),
    ]

    private static let defaultsKey = "permissions-levels-v1"

    @Published var levels: [String: Level] = [:] {
        didSet { persist() }
    }

    /// 全部逐项都是“跳过审批”时为真（Set All Bypass 总开关的状态就取这个）。
    var allBypass: Bool {
        Self.items.allSatisfy { level(for: $0.id) == .bypass }
    }

    /// 设置页 "Default Access Mode" 行右侧显示的当前模式（给设置页读，默认关时显示“询问后执行”）。
    /// 默认（全是“每次询问”）显示“询问后执行”；全跳过显示“全部跳过审批”；混搭显示“自定义”。
    var accessModeDescription: String {
        if allBypass { return "全部跳过审批" }
        if Self.items.allSatisfy({ level(for: $0.id) == .ask }) { return "询问后执行" }
        return "自定义"
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([String: Level].self, from: data) {
            levels = saved
        }
    }

    func level(for id: String) -> Level { levels[id] ?? .ask }

    func setLevel(_ level: Level, for id: String) {
        levels[id] = level
    }

    func setAll(_ level: Level) {
        for item in Self.items { levels[item.id] = level }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(levels) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

struct PermissionsView: View {
    /// 设置页 "Default Access Mode" 行右侧读这个值（默认关时为“询问后执行”）。
    /// 设置页那行要跟着变的话，包一层 @ObservedObject PermissionsStore.shared 再读它。
    static var accessModeDescription: String { PermissionsStore.shared.accessModeDescription }

    @ObservedObject private var permissions = PermissionsStore.shared
    @State private var configEnabled = MinisConfig.isEnabled
    @State private var showBypassRisk = false

    var body: some View {
        List {
            Section {
                // Set All Bypass 总开关（Minis 原版右上胶囊的本地落法：放顶部）。
                // 打开先弹风险确认，确认后才全置跳过审批；关掉全恢复为每次询问。
                Toggle(isOn: Binding(
                    get: { permissions.allBypass },
                    set: { on in
                        if on {
                            showBypassRisk = true
                        } else {
                            permissions.setAll(.ask)
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("全部跳过审批（Set All Bypass）")
                        Text("开着时智能体调工具不再逐项弹审批卡")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("全部跳过审批")
            } footer: {
                Text("只覆盖工具审批，不覆盖提问卡；敏感改动（启用连接器、授手机权限、定时自启）永远走审批卡，跳过审批也盖不住。")
            }
            .alert("打开全部跳过审批？", isPresented: $showBypassRisk) {
                Button("打开", role: .destructive) {
                    permissions.setAll(.bypass)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("打开后，智能体调用工具（执行服务器命令、抓网页、读写日历 / 提醒事项 / 剪贴板 / 位置 / 通讯录等）不再逐项弹审批卡，出了问题你只能事后在日志里查。提问卡照常弹，敏感改动也照常弹审批卡。")
            }

            Section("逐项权限") {
                ForEach(PermissionsStore.items) { item in
                    Picker(selection: Binding(
                        get: { permissions.level(for: item.id) },
                        set: { permissions.setLevel($0, for: item.id) }
                    )) {
                        ForEach(PermissionsStore.Level.allCases, id: \.self) { level in
                            Text(level.label).tag(level)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                            Text(item.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } footer: {
                Text("“禁止”= 智能体连调都调不了这个工具；“每次询问”= 每次调都弹审批卡；“跳过审批”= 直接执行。")
            }

            Section {
                Toggle("允许智能体改设置", isOn: $configEnabled)
                    .onChange(of: configEnabled) { MinisConfig.setEnabled($0) }
                NavigationLink {
                    MinisConfigView()
                } label: {
                    Text("智能体改设置")
                }
            } header: {
                Text("智能体改设置")
            } footer: {
                Text("默认关。关着时智能体完全不能改设置；开着时写操作走审批卡，改动记录在“智能体改设置 → 改动记录”里可查。")
            }
        }
        .navigationTitle("权限")
    }
}
