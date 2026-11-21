import SwiftUI

/// 扩展页 (original MarketplaceView): the agents, connectors and
/// skills installed on one computer, each list scrolling, with the
/// registry lists below the installed ones. Installing happens on
/// that computer; each bot turns connectors and skills on in its
/// settings.
///
/// Live probe on host 2.51.0 (2026-11-22): `skills` and
/// `marketSkills` answer (19 registry skills); `connectors`,
/// `marketConnectors`, `installConnector` and `removeConnector`
/// exist but fail on this host while its credential storage is
/// locked — those tabs show the host's reason, never invented rows.
/// The agents tab reads `hello.backends` (there is no standalone
/// `backends` method).
struct ExtensionsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var tab = 0
    @State private var showingCredentials = false
    @State private var viewingAgent: Backend?
    @State private var viewingConnector: MarketConnector?
    @State private var viewingSkill: MarketSkill?
    @State private var showingCordis = false
    @State private var didHandlePreview = false
    @State private var connectors: [InstalledConnector] = []
    @State private var connectorsError: String?
    @State private var connectorsLoaded = false
    @State private var skills: [InstalledSkill] = []
    @State private var skillsError: String?
    @State private var skillsLoaded = false
    @State private var marketSkills: [MarketSkill] = []
    @State private var marketSkillsError: String?
    @State private var marketSkillsLoaded = false
    @State private var marketConnectors: [MarketConnector] = []
    @State private var marketConnectorsError: String?
    @State private var marketConnectorsLoaded = false
    @State private var marketConnectorsNext: String?
    @State private var busySkill: String?
    @State private var busyConnector: String?

    /// Preview-only demo rows (seeded mode has no live host).
    private var isDemo: Bool { store.isPreview && store.connector.api == nil }

    private var backends: [Backend] {
        if isDemo { return ExtensionsDemo.backends }
        return (store.connector.hello?.backends ?? []).filter { $0.available || $0.installed == true || $0.curated == true }
    }

    private var query: String { search.trimmingCharacters(in: .whitespaces) }

    private var shownBackends: [Backend] {
        query.isEmpty ? backends : backends.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var shownSkills: [MarketSkill] {
        query.isEmpty ? marketSkills : marketSkills.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query)
        }
    }

    private var shownMarketConnectors: [MarketConnector] {
        query.isEmpty ? marketConnectors : marketConnectors.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.name.localizedCaseInsensitiveContains(query)
                || ($0.description ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private var installedCount: Int { connectors.count + skills.count }

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("扩展 linGyU"), trailing: AnyView(
                Button(L("凭证")) { showingCredentials = true }
                    .font(.body)
                    .foregroundStyle(Palette.text)
            )) {
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if connectorsLoaded && skillsLoaded {
                        Text(L("已安装 %d 个连接器和技能", installedCount))
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondary)
                    } else if !isDemo {
                        HStack(spacing: 8) {
                            Spinner(size: 14)
                            Text(L("正在读取已安装的扩展…"))
                                .font(.subheadline)
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    SearchField(text: $search, placeholder: L("搜索扩展…"))
                    TabChoice(titles: [L("智能体"), L("连接器"), L("技能")], selection: $tab)
                    if tab == 0 {
                        agentsTab
                    } else if tab == 1 {
                        connectorsTab
                    } else {
                        skillsTab
                    }
                    cordisSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .background(Palette.background)
        .task { await load() }
        .onAppear {
            if !didHandlePreview, case .seeded(let options) = store.previewMode {
                didHandlePreview = true
                if options.cordis {
                    showingCordis = true
                } else if options.connectorDetail {
                    viewingConnector = ExtensionsDemo.marketConnectors.first
                }
            }
        }
        .codyncSheet(isPresented: $showingCredentials) {
            NavigationStack { CredentialVaultView() }
        }
        .codyncSheet(isPresented: Binding(
            get: { viewingAgent != nil },
            set: { if !$0 { viewingAgent = nil } }
        )) {
            if let backend = viewingAgent {
                AgentDetailView(backend: backend)
            }
        }
        .codyncSheet(isPresented: Binding(
            get: { viewingConnector != nil },
            set: { if !$0 { viewingConnector = nil } }
        )) {
            if let connector = viewingConnector {
                MarketConnectorDetailView(connector: connector, onInstalled: { Task { await reloadConnectors() } })
            }
        }
        .codyncSheet(isPresented: Binding(
            get: { viewingSkill != nil },
            set: { if !$0 { viewingSkill = nil } }
        )) {
            if let skill = viewingSkill {
                MarketSkillDetailView(skill: skill, onInstalled: { Task { await reloadSkills() } })
            }
        }
        .codyncSheet(isPresented: $showingCordis) {
            CordisPanelView()
        }
    }

    /// Cordis (DSH 动态插件) entry. No separate tab: the panel opens
    /// as a sheet from here. See CordisViews.swift for why the panel
    /// is an honest empty state on this host.
    private var cordisSection: some View {
        CardSection(title: L("动态插件")) {
            Button { showingCordis = true } label: {
                MarketRowContent(title: L("Cordis 动态插件"), detail: L("智能体运行时定义的插件"), trailing: nil)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load

    private func load() async {
        if isDemo {
            connectors = ExtensionsDemo.installedConnectors
            connectorsLoaded = true
            skills = ExtensionsDemo.installedSkills
            skillsLoaded = true
            marketSkills = ExtensionsDemo.marketSkills
            marketSkillsLoaded = true
            marketConnectors = ExtensionsDemo.marketConnectors
            marketConnectorsLoaded = true
            return
        }
        guard let api = store.connector.api else { return }
        async let connectorsResult: [InstalledConnector] = api.connectors()
        async let skillsResult: [InstalledSkill] = api.skills()
        async let marketSkillsResult: [MarketSkill] = api.marketSkills()
        async let marketConnectorsResult: (items: [MarketConnector], next: String?) = api.marketConnectors(search: "")
        do { connectors = try await connectorsResult } catch { connectorsError = extensionErrorText(error) }
        connectorsLoaded = true
        do { skills = try await skillsResult } catch { skillsError = extensionErrorText(error) }
        skillsLoaded = true
        do { marketSkills = try await marketSkillsResult } catch { marketSkillsError = extensionErrorText(error) }
        marketSkillsLoaded = true
        do {
            let page = try await marketConnectorsResult
            marketConnectors = page.items
            marketConnectorsNext = page.next
        } catch { marketConnectorsError = extensionErrorText(error) }
        marketConnectorsLoaded = true
    }

    private func reloadConnectors() async {
        if isDemo { return }
        guard let api = store.connector.api else { return }
        connectorsLoaded = false
        connectorsError = nil
        marketConnectorsLoaded = false
        marketConnectorsError = nil
        do { connectors = try await api.connectors() } catch { connectorsError = extensionErrorText(error) }
        connectorsLoaded = true
        do {
            let page = try await api.marketConnectors(search: "")
            marketConnectors = page.items
            marketConnectorsNext = page.next
        } catch { marketConnectorsError = extensionErrorText(error) }
        marketConnectorsLoaded = true
    }

    private func reloadSkills() async {
        if isDemo { return }
        guard let api = store.connector.api else { return }
        skillsLoaded = false
        skillsError = nil
        marketSkillsLoaded = false
        marketSkillsError = nil
        do { skills = try await api.skills() } catch { skillsError = extensionErrorText(error) }
        skillsLoaded = true
        do { marketSkills = try await api.marketSkills() } catch { marketSkillsError = extensionErrorText(error) }
        marketSkillsLoaded = true
    }

    // MARK: - Agents tab

    private var agentsTab: some View {
        Group {
            if store.connector.hello?.backends == nil, !isDemo {
                DisabledCard(
                    title: L("电脑没有提供智能体列表"),
                    detail: L("这台电脑没有在连接里报出智能体。"))
            } else if shownBackends.isEmpty {
                Text(query.isEmpty ? L("还没有智能体") : L("没有找到匹配的智能体"))
                    .font(.body)
                    .foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(shownBackends) { backend in
                        Button { viewingAgent = backend } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ProviderMascot(providerId: backend.registry ?? backend.id, providerName: backend.name, size: 40)
                                Text(backend.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Palette.text)
                                    .lineLimit(1)
                                Text(agentStatus(backend))
                                    .font(.caption)
                                    .foregroundStyle(Palette.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func agentStatus(_ backend: Backend) -> String {
        if backend.needsNode { return L("需要先装 Node.js") }
        if !backend.available, backend.installed != true { return L("未安装") }
        if backend.signedIn == true { return L("已登录") }
        return L("未登录")
    }

    // MARK: - Connectors tab

    private var connectorsTab: some View {
        Group {
            CardSection(title: L("已安装")) {
                if !connectorsLoaded {
                    CardRow { Spinner(size: 16) }
                } else if let error = connectorsError {
                    CardRow {
                        DisabledText(
                            title: L("无法读取已安装的连接器"),
                            detail: error)
                    }
                } else if connectors.isEmpty {
                    CardRow {
                        Text(L("还没有安装连接器"))
                            .foregroundStyle(Palette.secondary)
                    }
                } else {
                    ForEach(connectors) { connector in
                        InstalledConnectorRow(connector: connector, busy: busyConnector == connector.id) {
                            await removeConnector(connector)
                        }
                        if connector.id != connectors.last?.id { Hairline() }
                    }
                }
            }
            CardSection(title: L("市场")) {
                if !marketConnectorsLoaded {
                    CardRow { Spinner(size: 16) }
                } else if let error = marketConnectorsError {
                    CardRow {
                        DisabledText(
                            title: L("无法读取连接器市场"),
                            detail: error)
                    }
                } else if shownMarketConnectors.isEmpty {
                    CardRow {
                        Text(query.isEmpty ? L("市场里还没有连接器") : L("没有找到匹配的连接器"))
                            .foregroundStyle(Palette.secondary)
                    }
                } else {
                    ForEach(shownMarketConnectors) { connector in
                        Button { viewingConnector = connector } label: {
                            MarketRowContent(title: connector.title, detail: connector.description ?? "", trailing: connector.installed ? L("已安装") : nil)
                        }
                        .buttonStyle(.plain)
                        if connector.id != shownMarketConnectors.last?.id { Hairline() }
                    }
                    if let next = marketConnectorsNext, !next.isEmpty {
                        CardRow {
                            Button(L("加载更多")) { Task { await loadMoreConnectors(cursor: next) } }
                                .buttonStyle(.plain)
                                .foregroundStyle(Palette.text)
                        }
                    }
                }
            }
        }
    }

    private func loadMoreConnectors(cursor: String) async {
        guard let api = store.connector.api else { return }
        do {
            let page = try await api.marketConnectors(search: "", cursor: cursor)
            marketConnectors.append(contentsOf: page.items)
            marketConnectorsNext = page.next
        } catch {
            marketConnectorsError = extensionErrorText(error)
        }
    }

    private func removeConnector(_ connector: InstalledConnector) async {
        guard let api = store.connector.api else { return }
        busyConnector = connector.id
        do {
            try await api.removeConnector(id: connector.id)
            await reloadConnectors()
        } catch {
            connectorsError = extensionErrorText(error)
        }
        busyConnector = nil
    }

    // MARK: - Skills tab

    private var skillsTab: some View {
        Group {
            CardSection(title: L("已安装")) {
                if !skillsLoaded {
                    CardRow { Spinner(size: 16) }
                } else if let error = skillsError {
                    CardRow {
                        DisabledText(
                            title: L("无法读取已安装的技能"),
                            detail: error)
                    }
                } else if skills.isEmpty {
                    CardRow {
                        Text(L("还没有安装技能"))
                            .foregroundStyle(Palette.secondary)
                    }
                } else {
                    ForEach(skills) { skill in
                        CardRow {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(skill.name)
                                        .foregroundStyle(Palette.text)
                                    if !skill.description.isEmpty {
                                        Text(skill.description)
                                            .font(.caption)
                                            .foregroundStyle(Palette.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                if busySkill == skill.id {
                                    Spinner(size: 16)
                                } else {
                                    Button(L("移除")) { Task { await removeSkill(skill) } }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(Palette.danger)
                                }
                            }
                        }
                        if skill.id != skills.last?.id { Hairline() }
                    }
                }
            }
            CardSection(title: L("市场")) {
                if !marketSkillsLoaded {
                    CardRow { Spinner(size: 16) }
                } else if let error = marketSkillsError {
                    CardRow {
                        DisabledText(
                            title: L("无法读取技能市场"),
                            detail: error)
                    }
                } else if shownSkills.isEmpty {
                    CardRow {
                        Text(query.isEmpty ? L("市场里还没有技能") : L("没有找到匹配的技能"))
                            .foregroundStyle(Palette.secondary)
                    }
                } else {
                    ForEach(shownSkills) { skill in
                        CardRow {
                            HStack(spacing: 12) {
                                Button { viewingSkill = skill } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(skill.name)
                                            .foregroundStyle(Palette.text)
                                        if !skill.description.isEmpty {
                                            Text(skill.description)
                                                .font(.caption)
                                                .foregroundStyle(Palette.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                if skill.installed {
                                    Text(L("已安装"))
                                        .font(.caption)
                                        .foregroundStyle(Palette.secondary)
                                } else if busySkill == skill.id {
                                    Spinner(size: 16)
                                } else {
                                    Button(L("安装")) { Task { await installSkill(skill) } }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(Palette.text)
                                }
                            }
                        }
                        if skill.id != shownSkills.last?.id { Hairline() }
                    }
                }
            }
        }
    }

    private func installSkill(_ skill: MarketSkill) async {
        guard let api = store.connector.api else { return }
        busySkill = skill.id
        do {
            try await api.installSkill(source: skill.source)
            await reloadSkills()
        } catch {
            marketSkillsError = extensionErrorText(error)
        }
        busySkill = nil
    }

    private func removeSkill(_ skill: InstalledSkill) async {
        guard let api = store.connector.api else { return }
        busySkill = skill.id
        do {
            try await api.removeSkill(id: skill.id)
            await reloadSkills()
        } catch {
            skillsError = extensionErrorText(error)
        }
        busySkill = nil
    }
}

/// A host error as a user-facing line: the host's own message when it
/// has one, otherwise a generic retry line.
private func extensionErrorText(_ error: Error) -> String {
    if let callError = error as? HostCallError, let message = callError.hostMessage, !message.isEmpty {
        return message
    }
    return L("读取失败，请重试。")
}

/// A disabled block: a title, a reason, and nothing to tap. Used
/// wherever the host has no API for a tab, so the page never invents
/// rows.
private struct DisabledCard: View {
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.text)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct DisabledText: View {
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .foregroundStyle(Palette.text)
            Text(detail)
                .font(.caption)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarketRowContent: View {
    var title: String
    var detail: String
    var trailing: String?

    var body: some View {
        CardRow {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Palette.text)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let trailing {
                    Text(trailing)
                        .font(.caption)
                        .foregroundStyle(Palette.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.tertiary)
            }
        }
    }
}

private struct InstalledConnectorRow: View {
    var connector: InstalledConnector
    var busy: Bool
    var onRemove: () async -> Void

    var body: some View {
        CardRow {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(connector.name)
                        .foregroundStyle(Palette.text)
                    if !connector.description.isEmpty {
                        Text(connector.description)
                            .font(.caption)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(2)
                    }
                    Text(connector.kind.isEmpty ? L("连接器") : connector.kind)
                        .font(.caption)
                        .foregroundStyle(Palette.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if connector.needsSignIn {
                    Text(L("待登录"))
                        .font(.caption)
                        .foregroundStyle(Palette.warning)
                }
                if busy {
                    Spinner(size: 16)
                } else {
                    Button(L("移除")) { Task { await onRemove() } }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.danger)
                }
            }
        }
    }
}

/// One registry connector: its options, and install for the options
/// that need nothing typed. An option with required inputs cannot be
/// installed from the phone — the page says so instead of guessing.
private struct MarketConnectorDetailView: View {
    var connector: MarketConnector
    var onInstalled: () -> Void
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var installingOption: String?
    @State private var installError: String?
    @State private var showingReport = false

    /// The host market sends no compatibility block and no readme for
    /// a connector (MarketConnector carries only name/title/description/
    /// version/website/installed/options), so those sections say so
    /// instead of inventing them. Likewise the host has no version pins
    /// (no pins mechanism in codync-host 2.51.0) and no report service.
    private var hasVersion: Bool { !(connector.version ?? "").isEmpty }
    private var sourceURL: URL? {
        guard let website = connector.website, !website.isEmpty else { return nil }
        return URL(string: website)
    }

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: connector.title) {
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let description = connector.description, !description.isEmpty {
                        Text(description)
                            .font(.body)
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if connector.installed {
                        Text(L("已安装"))
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondary)
                    }
                    CardSection(title: L("详情")) {
                        if hasVersion {
                            CardRow { ValueRow(label: L("版本"), value: connector.version) }
                            Hairline()
                        }
                        CardRow {
                            if let url = sourceURL {
                                ValueRow(label: L("来源")) {
                                    Link(connector.website ?? "", destination: url)
                                        .foregroundStyle(Palette.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            } else {
                                ValueRow(label: L("来源"), value: hasVersion ? "\(connector.name)@\(connector.version ?? "")" : connector.name)
                            }
                        }
                    }
                    CardSection(title: L("兼容性")) {
                        CardRow {
                            DisabledText(
                                title: L("市场没有提供兼容性说明"),
                                detail: L("安装前请确认它能在你的电脑上运行。"))
                        }
                        Hairline()
                        CardRow {
                            DisabledText(
                                title: L("本机没有版本钉"),
                                detail: L("这台电脑不会把连接器固定在某个版本。"))
                        }
                    }
                    CardSection(title: L("说明文档")) {
                        CardRow {
                            DisabledText(
                                title: L("没有说明文档"),
                                detail: L("市场没有提供这个连接器的说明文档。"))
                        }
                    }
                    if connector.options.isEmpty {
                        DisabledCard(
                            title: L("这个连接器没有可选的安装方式"),
                            detail: L("请在电脑上安装。"))
                    } else {
                        CardSection(title: L("安装方式")) {
                            ForEach(connector.options) { option in
                                CardRow {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(option.label.isEmpty ? option.kind : option.label)
                                                    .foregroundStyle(Palette.text)
                                                Text(option.kind)
                                                    .font(.caption)
                                                    .foregroundStyle(Palette.tertiary)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            if installingOption == option.id {
                                                Spinner(size: 16)
                                            } else if option.inputs.contains(where: { $0.required }) {
                                                Text(L("需要填写配置"))
                                                    .font(.caption)
                                                    .foregroundStyle(Palette.secondary)
                                            } else {
                                                Button(L("安装")) { Task { await install(option: option) } }
                                                    .buttonStyle(.plain)
                                                    .foregroundStyle(Palette.text)
                                            }
                                        }
                                        if !option.inputs.isEmpty {
                                            Text(option.inputs.map(\.name).joined(separator: " · "))
                                                .font(.caption)
                                                .foregroundStyle(Palette.secondary)
                                        }
                                    }
                                }
                                if option.id != connector.options.last?.id { Hairline() }
                            }
                        }
                    }
                    CardSection(title: L("举报")) {
                        Button { showingReport = true } label: {
                            MarketRowContent(title: L("举报此连接器"), detail: L("有问题的内容、恶意行为或冒充，都可以举报。"), trailing: nil)
                        }
                        .buttonStyle(.plain)
                    }
                    if let installError {
                        Text(installError)
                            .font(.body)
                            .foregroundStyle(Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .background(Palette.background)
        .codyncSheet(isPresented: $showingReport) {
            PluginReportSheet(name: connector.name, version: connector.version)
        }
    }

    private func install(option: MarketInstallOption) async {
        guard let api = store.connector.api else { return }
        installingOption = option.id
        installError = nil
        do {
            _ = try await api.installConnector(registryName: connector.name, option: option.id, inputs: [:])
            onInstalled()
            dismiss()
        } catch {
            installError = extensionErrorText(error)
        }
        installingOption = nil
    }
}

/// One registry skill: what the market says about it, with the same
/// honest gaps as the connector detail — the host market sends no
/// compatibility info and no readme for a skill, the host has no
/// version pins, and there is no report service.
private struct MarketSkillDetailView: View {
    var skill: MarketSkill
    var onInstalled: () -> Void
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var installing = false
    @State private var installError: String?
    @State private var showingReport = false

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: skill.name) {
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !skill.description.isEmpty {
                        Text(skill.description)
                            .font(.body)
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if skill.installed {
                        Text(L("已安装"))
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondary)
                    }
                    CardSection(title: L("详情")) {
                        CardRow { ValueRow(label: L("来源"), value: skill.source) }
                    }
                    CardSection(title: L("兼容性")) {
                        CardRow {
                            DisabledText(
                                title: L("市场没有提供兼容性说明"),
                                detail: L("安装前请确认它能在你的电脑上运行。"))
                        }
                        Hairline()
                        CardRow {
                            DisabledText(
                                title: L("本机没有版本钉"),
                                detail: L("这台电脑不会把技能固定在某个版本。"))
                        }
                    }
                    CardSection(title: L("说明文档")) {
                        CardRow {
                            DisabledText(
                                title: L("没有说明文档"),
                                detail: L("市场没有提供这个技能的说明文档。"))
                        }
                    }
                    if !skill.installed {
                        CardSection(title: L("安装方式")) {
                            CardRow {
                                Button {
                                    Task { await install() }
                                } label: {
                                    HStack {
                                        Spacer()
                                        if installing {
                                            Spinner(size: 16)
                                        } else {
                                            Text(L("安装"))
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(Palette.text)
                                        }
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(installing)
                                .opacity(installing ? 0.5 : 1)
                            }
                        }
                    }
                    CardSection(title: L("举报")) {
                        Button { showingReport = true } label: {
                            MarketRowContent(title: L("举报此技能"), detail: L("有问题的内容、恶意行为或冒充，都可以举报。"), trailing: nil)
                        }
                        .buttonStyle(.plain)
                    }
                    if let installError {
                        Text(installError)
                            .font(.body)
                            .foregroundStyle(Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .background(Palette.background)
        .codyncSheet(isPresented: $showingReport) {
            PluginReportSheet(name: skill.name, version: nil)
        }
    }

    private func install() async {
        guard let api = store.connector.api else { return }
        installing = true
        installError = nil
        do {
            try await api.installSkill(source: skill.source)
            onInstalled()
            dismiss()
        } catch {
            installError = extensionErrorText(error)
        }
        installing = false
    }
}

/// One agent backend: its models, its own gear, the supplier format,
/// and creating a bot from it.
///
/// Supplier format (user decision): when installing or configuring an
/// agent, pick the interface format — OpenAI-compatible, Anthropic,
/// and so on — so an ACP agent can point at a supplier the user
/// configured themselves. The format only sets the format, never a
/// vendor preset. The supplier itself (address and key) is configured
/// in the agent's login on the computer: the host has no field for a
/// supplier format on `createBot`, so the choice is remembered on
/// this phone and the page says where the supplier is configured.
/// Wiring the choice into the agent's login profile is open work.
private struct AgentDetailView: View {
    var backend: Backend
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var models: AgentModels?
    @State private var modelsError: String?
    @State private var modelsLoaded = false
    @State private var gear: AgentGear?
    @State private var selectedModel: String?
    @State private var supplierFormat: String = "openai"
    @State private var creating = false
    @State private var createError: String?

    /// Interface formats, as identifiers — not translated strings:
    /// a format is a supplier type, like a backend name.
    static let supplierFormats: [(id: String, label: String)] = [
        ("openai", "OpenAI 兼容"),
        ("anthropic", "Anthropic"),
        ("gemini", "Gemini"),
    ]

    private var formatKey: String { "cn.lingyu.supplierFormat.\(backend.id)" }

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: backend.name) {
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        ProviderMascot(providerId: backend.registry ?? backend.id, providerName: backend.name, size: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            if let description = backend.description, !description.isEmpty {
                                Text(description)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if backend.needsNode {
                                Text(L("这台电脑还没有 Node.js，装好才能用。"))
                                    .font(.caption)
                                    .foregroundStyle(Palette.warning)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !backend.available, backend.installed != true {
                        DisabledCard(
                            title: L("这个智能体还没装在电脑上"),
                            detail: backend.installHint.isEmpty ? L("请先在电脑上安装。") : backend.installHint)
                    } else {
                        CardSection(title: L("新建智能体")) {
                            CardRow {
                                TextField(L("名字"), text: $name)
                                    .font(.body)
                            }
                            Hairline()
                            CardRow {
                                ValueRow(label: L("供应商格式"), detail: L("接口格式，不是厂商。供应商的地址与密钥在电脑上的智能体登录里配置。")) {
                                    ChoicePicker(selection: $supplierFormat, options: Self.supplierFormats.map { (id: $0.id, label: $0.label) })
                                }
                            }
                            Hairline()
                            CardRow {
                                if !modelsLoaded {
                                    HStack(spacing: 8) {
                                        Spinner(size: 14)
                                        Text(L("正在读取模型…"))
                                            .font(.subheadline)
                                            .foregroundStyle(Palette.secondary)
                                    }
                                } else if let error = modelsError {
                                    DisabledText(title: L("无法读取模型"), detail: error)
                                } else if let models, !models.models.isEmpty {
                                    ValueRow(label: L("模型")) {
                                        ChoicePicker(selection: Binding(
                                            get: { selectedModel ?? models.currentModelId ?? models.models[0].id },
                                            set: { selectedModel = $0 }
                                        ), options: models.models.map { (id: $0.id, label: $0.name) })
                                    }
                                } else {
                                    Text(L("这个智能体没有报出模型"))
                                        .foregroundStyle(Palette.secondary)
                                }
                            }
                            Hairline()
                            CardRow {
                                Button {
                                    Task { await create() }
                                } label: {
                                    HStack {
                                        Spacer()
                                        if creating {
                                            Spinner(size: 16)
                                        } else {
                                            Text(L("创建并开始对话"))
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(Palette.text)
                                        }
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(creating || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                            }
                        }
                        if let createError {
                            Text(createError)
                                .font(.body)
                                .foregroundStyle(Palette.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let gear, !gear.skills.isEmpty || !gear.connectors.isEmpty || !gear.rules.isEmpty || !gear.plugins.isEmpty {
                            CardSection(title: L("自带装备"), footer: L("这个智能体在电脑上自带的技能、连接器、规则和插件。")) {
                                if !gear.skills.isEmpty {
                                    CardRow { ValueRow(label: L("技能"), value: "\(gear.skills.count)") }
                                }
                                if !gear.connectors.isEmpty {
                                    CardRow { ValueRow(label: L("连接器"), value: "\(gear.connectors.count)") }
                                }
                                if !gear.rules.isEmpty {
                                    CardRow { ValueRow(label: L("规则"), value: "\(gear.rules.count)") }
                                }
                                if !gear.plugins.isEmpty {
                                    CardRow { ValueRow(label: L("插件"), value: "\(gear.plugins.count)") }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .background(Palette.background)
        .onAppear {
            if name.isEmpty { name = backend.name }
            supplierFormat = UserDefaults.standard.string(forKey: formatKey) ?? "openai"
        }
        .task { await loadModels() }
    }

    private func loadModels() async {
        if store.isPreview, store.connector.api == nil {
            models = ExtensionsDemo.agentModels
            modelsLoaded = true
            gear = ExtensionsDemo.agentGear
            return
        }
        guard let api = store.connector.api else { return }
        do {
            models = try await api.agentModels(backend: backend.id)
            gear = try? await api.agentGear(backend: backend.id)
        } catch {
            modelsError = extensionErrorText(error)
        }
        modelsLoaded = true
    }

    private func create() async {
        guard let api = store.connector.api else { return }
        creating = true
        createError = nil
        UserDefaults.standard.set(supplierFormat, forKey: formatKey)
        var draft = BotDraft()
        draft.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.backend = backend.id
        draft.cwd = ""
        draft.permission = "ask"
        draft.mode = "auto"
        draft.model = selectedModel ?? models?.currentModelId
        draft.modelOptions = [:]
        do {
            let bot = try await api.createBot(draft: draft)
            await MainActor.run {
                dismiss()
                store.openChat(botId: bot.id)
            }
        } catch {
            createError = L("创建失败，请重试。")
            creating = false
        }
    }
}

/// Preview-only demo rows (seeded mode has no live host). A row that
/// fails to decode is dropped, never a crash.
private enum ExtensionsDemo {
    private static func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T? {
        try? JSONDecoder().decode(type, from: Data(json.utf8))
    }

    static let backends: [Backend] = [
        """
        {"id":"opencode","name":"OpenCode","available":true,"command":"{bin} acp","installHint":"","registry":"opencode","description":"开源编程智能体","installed":true,"curated":true,"signedIn":true,"canInstall":true,"node":null,"loginProfiles":[],"loginProfileSignIn":"terminal","loginKeys":[]}
        """,
        """
        {"id":"claude","name":"Claude Code","available":false,"command":"","installHint":"请在电脑上安装。","registry":"claude-acp","description":"Anthropic 的编程智能体","installed":false,"curated":true,"signedIn":null,"canInstall":true,"node":null,"loginProfiles":[],"loginProfileSignIn":"terminal","loginKeys":[]}
        """,
    ].compactMap { decode(Backend.self, $0) }

    static let installedConnectors: [InstalledConnector] = [
        """
        {"id":"demo-notes","name":"笔记","description":"把对话里的要点写进笔记。","kind":"local","keys":[],"auth":null}
        """,
    ].compactMap { decode(InstalledConnector.self, $0) }

    static let installedSkills: [InstalledSkill] = [
        """
        {"id":"demo-review","name":"review","description":"写完代码先自查一遍。","source":"review","path":""}
        """,
    ].compactMap { decode(InstalledSkill.self, $0) }

    static let marketSkills: [MarketSkill] = [
        """
        {"source":"review","name":"review","description":"写完代码先自查一遍。","installed":true}
        """,
        """
        {"source":"plan-first","name":"plan-first","description":"动手前先写计划。","installed":false}
        """,
    ].compactMap { decode(MarketSkill.self, $0) }

    static let marketConnectors: [MarketConnector] = [
        """
        {"name":"demo-search","title":"网页搜索","description":"让智能体查网页。","version":"1.2.0","website":"https://example.com/demo-search","installed":false,"options":[{"id":"remote","kind":"remote","label":"远程服务","inputs":[]}]}
        """,
    ].compactMap { decode(MarketConnector.self, $0) }

    static let agentModels: AgentModels? = decode(AgentModels.self, """
    {"models":[{"id":"opencode/big-pickle","name":"OpenCode/Big Pickle"},{"id":"opencode/beam-free","name":"OpenCode/Beam Free"}],"currentModelId":"opencode/big-pickle","modes":[{"id":"build","name":"build","description":"默认智能体"},{"id":"plan","name":"plan","description":"只做计划，不改代码"}]}
    """)

    static let agentGear: AgentGear? = decode(AgentGear.self, """
    {"skills":[],"connectors":[],"rules":[],"plugins":[]}
    """)
}
