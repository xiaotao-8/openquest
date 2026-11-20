import Foundation
import SwiftUI

/// minis-config（Minis 移植）：智能体通过统一工具协议读写设置。
///
/// 源码出处：
/// - 读写/总开关/确认门：`~/workspace/reference/minis/src/android/app/src/main/java/com/openminis/app/config/ConfigBridge.kt`
///   （isEnabled 第一道门；总开关关了，所有调用在查字段前直接返回 permission_denied）、
///   `config/MinisConfigPermissionStore.kt`（总开关；注意：Minis 上游默认开，OpenQuest 按
///   “非核心功能默认关”改成默认关）、`config/confirm/ConfigConfirmationGate.kt`（写操作走审批卡）。
/// - 审计：`config/audit/ConfigAuditEntry.kt`（一条记录 = 时间 / 谁改 / 作用域 / 键 / 旧值→新值 /
///   状态 applied-rejected-timeout-reverted）、`config/audit/ConfigAuditLog.kt`（单独库、滚动上限 1000 条）。
/// 本地移植：总开关存 UserDefaults（键 `minis-config-enabled`，默认关）；审计存
/// Documents/minis-config-audit.json（JSON 数组，滚动上限 1000 条，最新在前）。
///
/// 接线说明（给协调员）：本文件只提供工具定义与执行入口，不改 AgentTools.swift。
/// AgentTools.definitions 里追加 `MinisConfig.toolDefinitions()`（只在总开关开时追加），
/// execute 里 `minis_config_get/set/list` 三个名字转给 `MinisConfig.handleToolCall(...)`；
/// 返回 `.needsApproval` 时由调用方按现有 ApprovalSheetView 弹审批卡，用户批准后再调
/// `applyApproved(store:pending:)`，拒绝调 `recordRejection(pending:)`。
enum MinisConfig {
    static let getName = "oq_config_get"
    static let setName = "oq_config_set"
    static let listName = "oq_config_list"

    // MARK: - 总开关（默认关；关了智能体完全不能改设置；开关本身不允许经 minis-config 改）

    private static let enabledDefaultsKey = "minis-config-enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledDefaultsKey) as? Bool ?? false
    }

    static func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: enabledDefaultsKey)
    }

    // MARK: - 可读写字段登记（Minis ConfigRegistry 的本地版：只登记这些键，别的键一律拒绝）

    struct Field {
        let path: String
        let displayName: String
        let description: String
        /// 敏感字段：启用连接器 / 授手机权限 / 定时自启——强制走审批卡，全部跳过审批也盖不住。
        let sensitive: Bool
    }

    /// 固定字段。`agent.<id>.*` / `connector.<id>.enabled` / `device.<id>.enabled` /
    /// `schedule.<id>.enabled` 是集合字段，path 栏写模式，实际键按模式展开。
    static let fields: [Field] = [
        Field(path: "language", displayName: "界面语言",
              description: "界面语言代码，如 zh-Hans、en", sensitive: false),
        Field(path: "dns.mode", displayName: "DNS 模式",
              description: "system（跟随系统）、aliyun、tencent、114、custom", sensitive: false),
        Field(path: "dns.custom", displayName: "自定义 DNS",
              description: "dns.mode 为 custom 时用的 DNS 地址", sensitive: false),
        Field(path: "agent.<id>.temperature", displayName: "智能体 Temperature",
              description: "0 到 2，越高回答越发散", sensitive: false),
        Field(path: "agent.<id>.topP", displayName: "智能体 Top-P",
              description: "0 到 1", sensitive: false),
        Field(path: "agent.<id>.effort", displayName: "智能体思考档位",
              description: "空=跟模型默认、off、low、medium、high", sensitive: false),
        Field(path: "agent.<id>.autoCompress", displayName: "智能体自动压缩",
              description: "true / false：上下文满了自动压缩", sensitive: false),
        Field(path: "agent.<id>.contextLength", displayName: "智能体上下文条数",
              description: "0=不限，最多带几条历史消息", sensitive: false),
        Field(path: "connector.<id>.enabled", displayName: "连接器开关",
              description: "启用某个连接器", sensitive: true),
        Field(path: "device.<id>.enabled", displayName: "手机能力开关",
              description: "授予某项手机能力（日历、提醒事项、照片、剪贴板、位置、通讯录）", sensitive: true),
        Field(path: "schedule.<id>.enabled", displayName: "定时任务开关",
              description: "启用某个定时自启任务", sensitive: true),
    ]

    /// 敏感键判定：`connector.*` / `device.*` / `schedule.*` 的写操作一律敏感。
    static func isSensitive(path: String) -> Bool {
        path.hasPrefix("connector.") || path.hasPrefix("device.") || path.hasPrefix("schedule.")
    }

    // MARK: - 读

    /// 读一个键。读也要求总开关开着（Minis：关了读也返回 permission_denied）。
    /// 未知键返回 nil。
    static func read(store: AppStore, path: String) -> String? {
        guard isEnabled else { return nil }
        return readRaw(store: store, path: path)
    }

    private static func readRaw(store: AppStore, path: String) -> String? {
        let parts = path.split(separator: ".").map(String.init)
        switch parts.first {
        case "language":
            return parts.count == 1 ? store.language : nil
        case "dns":
            if parts == ["dns", "mode"] { return store.dnsMode }
            if parts == ["dns", "custom"] { return store.dnsCustom }
            return nil
        case "agent":
            guard parts.count == 3, let id = UUID(uuidString: parts[1]),
                  let a = store.agent(id: id) else { return nil }
            switch parts[2] {
            case "temperature": return String(a.temperature)
            case "topP": return String(a.topP)
            case "effort": return a.effort
            case "autoCompress": return a.autoCompress ? "true" : "false"
            case "contextLength": return String(a.contextLength)
            default: return nil
            }
        case "connector":
            guard parts.count == 3, parts[2] == "enabled",
                  let c = store.connectors.first(where: { $0.id == parts[1] }) else { return nil }
            return c.enabled ? "true" : "false"
        case "device":
            guard parts.count == 3, parts[2] == "enabled",
                  let c = store.deviceCapabilities.first(where: { $0.id == parts[1] }) else { return nil }
            return c.enabled ? "true" : "false"
        case "schedule":
            guard parts.count == 3, parts[2] == "enabled",
                  let t = store.scheduledTasks.first(where: { $0.id.uuidString == parts[1] }) else { return nil }
            return t.enabled ? "true" : "false"
        default:
            return nil
        }
    }

    // MARK: - 写（走审批卡；全部跳过审批只覆盖普通写，敏感写永远要批）

    struct PendingChange: Equatable {
        let key: String
        let value: String
        let oldValue: String
        let sensitive: Bool
        let caption: String
    }

    enum WriteOutcome {
        case applied(old: String, new: String)
        case needsApproval(PendingChange)
        case denied(String)
    }

    /// 智能体写设置的主入口。调用方拿到 `.needsApproval` 就弹审批卡（现有 ApprovalSheetView），
    /// 用户批准后调 `applyApproved`，拒绝调 `recordRejection`；两种结果都进审计。
    static func requestWrite(store: AppStore, path: String, value: String,
                             actor: String, caption: String? = nil) -> WriteOutcome {
        guard isEnabled else {
            let msg = "设置接口没开：去设置 → 权限里打开“允许智能体改设置”再试。"
            record(actor: actor, key: path, oldValue: "", newValue: value, status: .rejected)
            return .denied(msg)
        }
        guard let old = readRaw(store: store, path: path) else {
            return .denied("没有这个设置项：\(path)。可改的项用 oq_config_list 查。")
        }
        guard validate(path: path, value: value) else {
            return .denied("值不对：\(path) 不能写成 \(value)。")
        }
        let pending = PendingChange(key: path, value: value, oldValue: old,
                                    sensitive: isSensitive(path: path),
                                    caption: caption ?? "")
        // 敏感改动强制走审批卡；普通改动在全部跳过审批开时直接执行，否则也走审批卡。
        if pending.sensitive || !PermissionsStore.shared.allBypass {
            return .needsApproval(pending)
        }
        apply(store: store, pending: pending)
        record(actor: actor, key: path, oldValue: old, newValue: value, status: .applied)
        return .applied(old: old, new: value)
    }

    /// 审批卡上用户点了批准后调这个，真正落盘并记审计。返回 false = 键已不在（目标被删了）。
    @discardableResult
    static func applyApproved(store: AppStore, pending: PendingChange, actor: String) -> Bool {
        guard readRaw(store: store, path: pending.key) != nil else { return false }
        apply(store: store, pending: pending)
        record(actor: actor, key: pending.key, oldValue: pending.oldValue,
               newValue: pending.value, status: .applied)
        return true
    }

    /// 审批卡上用户点了拒绝后调这个，只记审计，不改任何设置。
    static func recordRejection(pending: PendingChange, actor: String) {
        record(actor: actor, key: pending.key, oldValue: pending.oldValue,
               newValue: pending.value, status: .rejected)
    }

    private static func validate(path: String, value: String) -> Bool {
        let parts = path.split(separator: ".").map(String.init)
        func number(_ v: String, range: ClosedRange<Double>) -> Bool {
            guard let d = Double(v) else { return false }
            return range.contains(d)
        }
        func bool(_ v: String) -> Bool { v == "true" || v == "false" }
        if path == "language" { return !value.trimmingCharacters(in: .whitespaces).isEmpty }
        if path == "dns.mode" {
            return ["system", "aliyun", "tencent", "114", "custom"].contains(value)
        }
        if path == "dns.custom" { return !value.trimmingCharacters(in: .whitespaces).isEmpty }
        if parts.first == "agent", parts.count == 3 {
            switch parts[2] {
            case "temperature": return number(value, range: 0...2)
            case "topP": return number(value, range: 0...1)
            case "effort": return ["", "off", "low", "medium", "high"].contains(value)
            case "autoCompress": return bool(value)
            case "contextLength":
                guard let n = Int(value) else { return false }
                return (0...100).contains(n)
            default: return false
            }
        }
        if parts.first == "connector" || parts.first == "device" || parts.first == "schedule" {
            return parts.count == 3 && parts[2] == "enabled" && bool(value)
        }
        return false
    }

    /// 真正写值（已通过审批或全部跳过审批才到这里）。写完立刻落盘。
    private static func apply(store: AppStore, pending: PendingChange) {
        let parts = pending.key.split(separator: ".").map(String.init)
        switch parts.first {
        case "language":
            store.language = pending.value
            store.save()
        case "dns":
            if parts == ["dns", "mode"] {
                store.setDNS(mode: pending.value)
            } else if parts == ["dns", "custom"] {
                store.setDNS(mode: store.dnsMode, custom: pending.value)
            }
        case "agent":
            guard parts.count == 3, let id = UUID(uuidString: parts[1]),
                  let i = store.agents.firstIndex(where: { $0.id == id }) else { return }
            switch parts[2] {
            case "temperature": store.agents[i].temperature = Double(pending.value) ?? 1.0
            case "topP": store.agents[i].topP = Double(pending.value) ?? 1.0
            case "effort": store.agents[i].effort = pending.value
            case "autoCompress": store.agents[i].autoCompress = pending.value == "true"
            case "contextLength": store.agents[i].contextLength = Int(pending.value) ?? 0
            default: return
            }
            store.save()
        case "connector":
            if parts.count == 3, parts[2] == "enabled" {
                store.setConnectorEnabled(id: parts[1], pending.value == "true")
            }
        case "device":
            if parts.count == 3, parts[2] == "enabled" {
                store.setDeviceCapability(id: parts[1], on: pending.value == "true")
            }
        case "schedule":
            if parts.count == 3, parts[2] == "enabled",
               let id = UUID(uuidString: parts[1]) {
                store.setScheduledTaskEnabled(id: id, pending.value == "true")
            }
        default:
            break
        }
    }

    // MARK: - 统一工具协议（给 AgentTools.definitions / execute 接的定义与入口）

    static func toolDefinitions() -> [[String: Any]] {
        [
            [
                "type": "function",
                "function": [
                    "name": getName,
                    "description": "读一个设置项的值。path 如 language、dns.mode、agent.<id>.temperature、connector.<id>.enabled。先调 oq_config_list 看能读哪些。",
                    "parameters": ["type": "object", "properties": [
                        "path": ["type": "string", "description": "设置项路径"]
                    ], "required": ["path"]],
                ],
            ],
            [
                "type": "function",
                "function": [
                    "name": setName,
                    "description": "改一个设置项。写操作会弹审批卡给用户批，批了才生效；敏感改动（启用连接器、授手机权限、定时自启）一定会弹卡，跳过审批也盖不住。设置接口总开关关着时直接拒绝。",
                    "parameters": ["type": "object", "properties": [
                        "path": ["type": "string", "description": "设置项路径"],
                        "value": ["type": "string", "description": "新值（字符串形式）"],
                        "caption": ["type": "string", "description": "改动说明（一句话，给用户看）"]
                    ], "required": ["path", "value"]],
                ],
            ],
            [
                "type": "function",
                "function": [
                    "name": listName,
                    "description": "列出智能体能读/改的设置项（路径、说明、是否敏感）。",
                    "parameters": ["type": "object", "properties": [:]],
                ],
            ],
        ]
    }

    /// 工具调用入口（AgentTools.execute 转调）。读与 list 直接回文本；
    /// 写在需要审批时返回以 `NEEDS_APPROVAL:` 开头的标记串，调用方据此弹审批卡——
    /// 卡上批了再调 applyApproved，拒绝调 recordRejection。标记串里只放键与新值，不放敏感内容。
    static func handleToolCall(name: String, argumentsJSON: String,
                               store: AppStore, agentName: String) -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "参数不对" }
        switch name {
        case listName:
            guard isEnabled else { return "设置接口没开" }
            return fields.map { f in
                "\(f.path) — \(f.displayName)：\(f.description)\(f.sensitive ? "（敏感，改动必弹审批卡）" : "")"
            }.joined(separator: "\n")
        case getName:
            guard let path = obj["path"] as? String, !path.isEmpty else { return "参数不对：缺 path" }
            guard isEnabled else { return "设置接口没开：去设置 → 权限里打开“允许智能体改设置”再试。" }
            guard let v = readRaw(store: store, path: path) else { return "没有这个设置项：\(path)" }
            return "\(path) = \(v)"
        case setName:
            guard let path = obj["path"] as? String, !path.isEmpty,
                  let value = obj["value"] as? String
            else { return "参数不对：oq_config_set 要 path 和 value" }
            let caption = obj["caption"] as? String ?? ""
            switch requestWrite(store: store, path: path, value: value,
                                actor: "智能体 \(agentName)", caption: caption) {
            case .applied(let old, let new):
                return "已改：\(path) 从 \(old) 改成 \(new)"
            case .denied(let msg):
                return msg
            case .needsApproval(let pending):
                return "NEEDS_APPROVAL:\(pending.key)=\(pending.value)（旧值 \(pending.oldValue)）"
            }
        default:
            return "未知工具 \(name)"
        }
    }

    // MARK: - 审计日志（Minis ConfigAuditLog：滚动上限 1000 条，最新在前）

    enum AuditStatus: String, Codable { case applied, rejected }

    struct AuditEntry: Codable, Identifiable {
        var id: UUID = UUID()
        var at: Date = Date()
        var actor: String
        var scope: String
        var key: String
        var oldValue: String
        var newValue: String
        var status: AuditStatus
        var caption: String = ""
    }

    private static let maxAuditRows = 1000

    private static var auditFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("minis-config-audit.json")
    }

    static func auditEntries() -> [AuditEntry] {
        guard let data = try? Data(contentsOf: auditFileURL),
              let list = try? JSONDecoder().decode([AuditEntry].self, from: data)
        else { return [] }
        return list.sorted { $0.at > $1.at }
    }

    static func clearAudit() {
        try? FileManager.default.removeItem(at: auditFileURL)
    }

    private static func record(actor: String, key: String, oldValue: String,
                               newValue: String, status: AuditStatus) {
        let scope = key.split(separator: ".").first.map(String.init) ?? ""
        var list = auditEntries()
        list.insert(AuditEntry(actor: actor, scope: scope, key: key,
                               oldValue: oldValue, newValue: newValue, status: status), at: 0)
        if list.count > maxAuditRows { list = Array(list.prefix(maxAuditRows)) }
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: auditFileURL, options: .atomic)
        }
    }
}

// MARK: - 设置页入口：minis-config 页（总开关 + 可改项一览 + 审计日志）

struct MinisConfigView: View {
    @EnvironmentObject var store: AppStore
    @State private var enabled = MinisConfig.isEnabled
    @State private var showClearAudit = false

    var body: some View {
        List {
            Section {
                Toggle("允许智能体改设置", isOn: $enabled)
                    .onChange(of: enabled) { MinisConfig.setEnabled($0) }
            } header: {
                Text("总开关")
            } footer: {
                Text(enabled
                     ? "开着：智能体能通过设置接口读写下面这些设置，写操作会弹审批卡给你批。"
                     : "关着（默认）：智能体完全不能改设置，调工具会直接收到拒绝；开关本身只能你在这里改。")
            }
            Section("智能体能改的设置") {
                ForEach(MinisConfig.fields, id: \.path) { f in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(f.displayName)
                            if f.sensitive {
                                Text("敏感").font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.red.opacity(0.12), in: Capsule())
                            }
                        }
                        Text(f.path).font(.caption).foregroundStyle(.secondary)
                        Text(f.description).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                Text("集合项按实际 id 展开，如 agent.<智能体 id>.temperature；完整列表智能体调 oq_config_list 自己查。")
            }
            Section {
                NavigationLink {
                    ConfigAuditView()
                } label: {
                    HStack {
                        Text("改动记录")
                        Spacer()
                        Text("\(MinisConfig.auditEntries().count) 条")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("谁在什么时候改了什么、旧值改成新值，都记在这里，最多留最近 1000 条。")
            }
        }
        .navigationTitle("智能体改设置")
    }
}

/// 审计日志页：时间、谁改、改了什么、旧值→新值、结果（已改 / 已拒绝）。
struct ConfigAuditView: View {
    @State private var entries = MinisConfig.auditEntries()
    @State private var showClear = false

    var body: some View {
        List {
            if entries.isEmpty {
                Text("还没有改动记录。智能体或你改设置后，这里会记下时间、改了什么和旧值→新值。")
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { e in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(e.actor).font(.subheadline).fontWeight(.medium)
                        Spacer()
                        Text(e.status == .applied ? "已改" : "已拒绝")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(e.status == .applied ? Palette.running : .red)
                    }
                    Text(e.key).font(.caption).foregroundStyle(.secondary)
                    Text("\(e.oldValue.isEmpty ? "（空）" : e.oldValue) → \(e.newValue.isEmpty ? "（空）" : e.newValue)")
                        .font(.system(size: 12, design: .monospaced))
                    Text(e.at, style: .date)
                    Text(e.at, style: .time)
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("改动记录")
        .toolbar {
            if !entries.isEmpty {
                Button("清空") { showClear = true }
            }
        }
        .alert("清空全部改动记录？", isPresented: $showClear) {
            Button("清空", role: .destructive) {
                MinisConfig.clearAudit()
                entries = []
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清空后之前的改动记录就找不回来了。")
        }
        .onAppear { entries = MinisConfig.auditEntries() }
    }
}
