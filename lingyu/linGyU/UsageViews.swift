import SwiftUI

/// 用量页 (original UsageView): one computer's usage — what its
/// agents have used — from the host `usage` method, with the
/// show/hide chooser behind a button. This replaces the honest
/// empty state in StateView's old UsageView; the coordinator swaps
/// it in.
///
/// Live probe on host 2.51.0 (2026-11-22): `usage {refresh}`
/// answers `{"providers": [], "services": [{"id": "opencode",
/// "name": "OpenCode", "registry": "opencode", "shown": true}]}` —
/// no provider has a reading on this computer yet, so the page
/// shows the honest empty state until one does. `setUsageShown` and
/// `setUsageOrder` answer too.
///
/// Not here, by design: the FishPocket-style token ledger (today /
/// 7 days / 30 days input / output / call counts) — the host's
/// `usage` carries no such numbers, so the page says so in its
/// footer instead of inventing them.
struct HostUsageView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var usage: Usage?
    @State private var loadError: String?
    @State private var loading = true
    @State private var arranging = false

    /// Preview-only demo rows (seeded mode has no live host).
    private var isDemo: Bool { store.isPreview && store.connector.api == nil }

    private var services: [UsageService] { usage?.services ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: L("用量"), trailing: AnyView(
                HStack(spacing: 4) {
                    if !arranging {
                        Button(action: { Task { await load(refresh: true) } }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.iconButton)
                        .accessibilityLabel(L("刷新"))
                        .disabled(loading)
                    }
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.iconButton)
                    .accessibilityLabel(L("关闭"))
                }
            ))
            if !store.connector.isPaired, !isDemo {
                VStack(spacing: 14) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundStyle(Palette.tertiary)
                    Text(L("还没有连接电脑"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.text)
                    Text(L("连接电脑后，这里会显示用量。"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else if loading {
                VStack(spacing: 12) {
                    Spinner(size: 20)
                    Text(L("正在读取用量…"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                VStack(spacing: 12) {
                    Text(L("无法读取用量"))
                        .font(.headline)
                        .foregroundStyle(Palette.text)
                    Text(loadError)
                        .font(.body)
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else if let usage {
                usageBody(usage)
            }
        }
        .background(Palette.background)
        .task { await load(refresh: true) }
    }

    private func load(refresh: Bool) async {
        if isDemo {
            usage = UsageDemo.usage
            loading = false
            return
        }
        guard let api = store.connector.api else {
            loadError = L("还没有连接电脑")
            loading = false
            return
        }
        loading = true
        loadError = nil
        do {
            usage = try await api.usage(refresh: refresh)
        } catch {
            loadError = usageErrorText(error)
        }
        loading = false
    }

    private func usageErrorText(_ error: Error) -> String {
        if let callError = error as? HostCallError {
            if callError.isUnknownMethod {
                return L("电脑端未提供用量数据")
            }
            if let message = callError.hostMessage, !message.isEmpty {
                return message
            }
        }
        return L("读取失败，请重试。")
    }

    @ViewBuilder
    private func usageBody(_ usage: Usage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if arranging, !services.isEmpty {
                    arrangingBody
                } else if usage.providers.isEmpty {
                    VStack(spacing: 12) {
                        Text(L("还没有用量数据"))
                            .font(.headline)
                            .foregroundStyle(Palette.text)
                        Text(L("还没有用量数据：电脑上没有配置带额度查询的供应商"))
                            .font(.body)
                            .foregroundStyle(Palette.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    ForEach(usage.providers) { provider in
                        ProviderUsageCard(provider: provider)
                    }
                }
                if !arranging, !services.isEmpty {
                    Button {
                        withAnimation { arranging = true }
                    } label: {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                            Text(L("选择与排列"))
                        }
                        .foregroundStyle(Palette.text)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 2)
                }
                Text(L("这里只显示供应商的额度窗口。按天统计的 token 账本，电脑端没有提供。"))
                    .font(.caption)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    /// The show/hide chooser (original UsageView, edit mode): one row
    /// per agent with its switch, and up/down moves for the order.
    /// The host keeps the choice, so every app follows it.
    private var arrangingBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("显示哪些智能体"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Spacer()
                Button(L("完成")) {
                    withAnimation { arranging = false }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.text)
            }
            .padding(.leading, 2)
            CardSection(footer: L("默认显示你的智能体在用的供应商。")) {
                ForEach(Array(services.enumerated()), id: \.element.id) { index, service in
                    CardRow {
                        HStack(spacing: 8) {
                            ProviderMascot(providerId: service.registry ?? service.id, providerName: service.name, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(service.name)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.text)
                                    .lineLimit(1)
                                if hasNoReading(service) {
                                    Text(L("暂无读数"))
                                        .font(.caption)
                                        .foregroundStyle(Palette.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Toggle("", isOn: Binding(
                                get: { service.shown },
                                set: { shown in Task { await setShown(service, shown: shown) } }
                            ))
                            .labelsHidden()
                            .toggleStyle(.codync)
                            VStack(spacing: 2) {
                                Button {
                                    Task { await moveService(service, by: -1) }
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(index == 0 ? Palette.tertiary.opacity(0.4) : Palette.secondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(index == 0)
                                Button {
                                    Task { await moveService(service, by: 1) }
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(index == services.count - 1 ? Palette.tertiary.opacity(0.4) : Palette.secondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(index == services.count - 1)
                            }
                        }
                    }
                    if index != services.count - 1 { Hairline() }
                }
            }
        }
    }

    private func hasNoReading(_ service: UsageService) -> Bool {
        guard let provider = usage?.providers.first(where: { $0.id == service.id }) else { return true }
        return !provider.hasReading
    }

    private func setShown(_ service: UsageService, shown: Bool) async {
        if isDemo {
            if let index = usage?.services?.firstIndex(where: { $0.id == service.id }) {
                usage?.services?[index].shown = shown
            }
            return
        }
        guard let api = store.connector.api else { return }
        do {
            usage = try await api.setUsageShown(id: service.id, shown: shown)
        } catch {
            loadError = usageErrorText(error)
        }
    }

    private func moveService(_ service: UsageService, by offset: Int) async {
        guard var ids = usage?.services?.map(\.id) else { return }
        guard let from = ids.firstIndex(of: service.id) else { return }
        let to = from + offset
        guard ids.indices.contains(to) else { return }
        ids.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        if isDemo {
            usage?.services?.sort { lhs, rhs in
                (ids.firstIndex(of: lhs.id) ?? 0) < (ids.firstIndex(of: rhs.id) ?? 0)
            }
            return
        }
        guard let api = store.connector.api else { return }
        do {
            usage = try await api.setUsageOrder(ids: ids)
        } catch {
            loadError = usageErrorText(error)
        }
    }
}

/// One provider's card (original ProviderLimits): its name, each
/// login's windows with a bar and a reset line, and the source.
private struct ProviderUsageCard: View {
    var provider: UsageProvider

    var body: some View {
        CardSection {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ProviderMascot(providerId: provider.registry ?? provider.id, providerName: provider.name, size: 28)
                    Text(provider.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if provider.failedAt != nil {
                        Text(L("数据可能过期"))
                            .font(.caption)
                            .foregroundStyle(Palette.warning)
                    }
                }
                ForEach(provider.logins) { login in
                    if login.name != nil {
                        Text(login.name ?? "")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.secondary)
                    }
                    ForEach(login.windows) { window in
                        UsageWindowRow(window: window)
                    }
                    if login.isOutOfDate {
                        Text(L("上次检查失败，显示的是之前的数据。"))
                            .font(.caption)
                            .foregroundStyle(Palette.warning)
                    }
                }
                Text(L("来源 %@ · 更新于 %@", provider.source, updatedText))
                    .font(.caption)
                    .foregroundStyle(Palette.tertiary)
            }
            .padding(16)
        }
    }

    private var updatedText: String {
        guard provider.updatedAt > 0 else { return L("未知") }
        let date = Date(timeIntervalSince1970: TimeInterval(provider.updatedAt) / 1000)
        return Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct UsageWindowRow: View {
    var window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(window.label)
                    .font(.subheadline)
                    .foregroundStyle(Palette.text)
                Spacer(minLength: 8)
                if let text = window.text {
                    Text(text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.text)
                } else {
                    Text("\(Int(window.percent.rounded()))%")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.text)
                        .monospacedDigit()
                }
            }
            if window.text == nil {
                UsageTicks(percent: window.percent, tint: Palette.accentFill, height: 8)
            }
            if let resets = resetText {
                Text(resets)
                    .font(.caption)
                    .foregroundStyle(Palette.secondary)
            }
        }
    }

    private var resetText: String? {
        if let date = window.resetDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return L("重置于 %@", formatter.string(from: date))
        }
        if let resetsText = window.resetsText, !resetsText.isEmpty {
            return L("重置于 %@", resetsText)
        }
        return nil
    }
}

/// Preview-only demo rows (seeded mode has no live host).
private enum UsageDemo {
    static let usage: Usage? = {
        let json = """
        {"providers":[{"id":"opencode","name":"OpenCode","windows":[{"id":"5h","label":"5 小时","percent":42,"resetsAt":1763788000000},{"id":"week","label":"每周","percent":18,"resetsAt":1764374800000}],"source":"opencode","updatedAt":1763770000000,"registry":"opencode"}],"services":[{"id":"opencode","name":"OpenCode","shown":true,"registry":"opencode"}]}
        """
        return try? JSONDecoder().decode(Usage.self, from: Data(json.utf8))
    }()
}
