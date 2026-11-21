import Foundation

/// The local mirror of the host's bots and entries, driven by the events
/// subscription (§5). Rows are keyed by `bot.id` and `(botId, seq)`; an
/// incoming row with an older `rev` than the stored row is ignored; the same
/// event applied twice is a no-op. The `rev` cursor is persisted atomically
/// with the bot rows (one UserDefaults blob) so a crash cannot leave `rev`
/// ahead of the rows. Entry rows are kept in memory in Phase 1 and re-seeded
/// from `history()` when a chat opens; the cursor still advances past them.
@MainActor
final class EventMirror: ObservableObject {
    @Published private(set) var bots: [Bot] = []
    @Published private(set) var entriesByBot: [String: [Entry]] = [:]
    @Published private(set) var rev: Int64 = 0
    @Published private(set) var isSyncing = false
    @Published private(set) var icons: [String: JSONValue] = [:]
    @Published private(set) var iconsRevision = 0
    @Published private(set) var computerName: String?

    private let storeKey = "cn.lingyu.mirror.v1"
    private var subscribeTask: Task<Void, Never>?
    private var needsResync = false
    private var catchUpExpected = 0
    private var catchUpReceived = 0

    private struct PersistedMirror: Codable {
        var rev: Int64
        var bots: [Bot]
    }

    init() {
        load()
    }

    // MARK: - Subscription loop

    func start(api: HostAPI) {
        stop()
        subscribeTask = Task {
            while !Task.isCancelled {
                needsResync = false
                do {
                    let stream = api.events(since: rev)
                    for try await event in stream {
                        apply(event)
                        if needsResync || Task.isCancelled { break }
                    }
                } catch {
                    // The channel supervisor reconnects; resubscribe after a pause.
                    if Task.isCancelled { break }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
                if needsResync {
                    rev = 0
                    bots.removeAll()
                    entriesByBot.removeAll()
                    save()
                }
            }
        }
    }

    func stop() {
        subscribeTask?.cancel()
        subscribeTask = nil
    }

    /// Clears the mirror (in-memory rows + persisted cursor/bots). Used by
    /// the preview modes so a seeded run never leaks into a live run.
    func reset() {
        subscribeTask?.cancel()
        subscribeTask = nil
        rev = 0
        bots.removeAll()
        entriesByBot.removeAll()
        icons.removeAll()
        iconsRevision = 0
        computerName = nil
        isSyncing = false
        UserDefaults.standard.removeObject(forKey: storeKey)
    }

    // MARK: - Lookups

    func bot(id: String) -> Bot? {
        bots.first { $0.id == id }
    }

    func entries(for botId: String) -> [Entry] {
        entriesByBot[botId] ?? []
    }

    var leadBot: Bot? {
        bots.first { $0.lead } ?? bots.first
    }

    var unreadTotal: Int {
        bots.reduce(0) { $0 + $1.unread }
    }

    var waitingTotal: Int {
        bots.reduce(0) { $0 + $1.waiting }
    }

    var workingBots: [Bot] {
        bots.filter { $0.isWorking }
    }

    // MARK: - Applying events

    func apply(_ event: HostEvent) {
        switch event {
        case .hello(let helloRev, let catchUp, _):
            if helloRev > rev { rev = helloRev }
            catchUpExpected = catchUp
            catchUpReceived = 0
            isSyncing = catchUp > 0
        case .icons(let newIcons, let revision):
            icons = newIcons
            iconsRevision = revision
        case .bot(let bot):
            upsertBot(bot)
        case .botDeleted(let id, let deletedRev):
            bots.removeAll { $0.id == id }
            entriesByBot.removeValue(forKey: id)
            if deletedRev > rev { rev = deletedRev }
            save()
        case .entry(let entry):
            upsertEntry(entry)
        case .threadEntry:
            break
        case .usage, .screen, .artifact, .network, .callCue:
            break
        case .name(let name):
            computerName = name
        case .autoOrder:
            break
        case .resync:
            needsResync = true
        case .undecodable, .skipped:
            break
        }
        catchUpReceived += 1
        if isSyncing && catchUpReceived >= catchUpExpected {
            isSyncing = false
        }
    }

    private func upsertBot(_ bot: Bot) {
        guard !bot.id.isEmpty else { return }
        if let index = bots.firstIndex(where: { $0.id == bot.id }) {
            if bot.rev < bots[index].rev { return }
            bots[index] = bot
        } else {
            bots.append(bot)
        }
        sortBots()
        if bot.rev > rev { rev = bot.rev }
        save()
    }

    private func upsertEntry(_ entry: Entry) {
        guard !entry.id.isEmpty else { return }
        var rows = entriesByBot[entry.botId] ?? []
        // A host user entry replaces the optimistic local entry with the
        // same clientNonce.
        if entry.kind == "user", let nonce = entry.data.clientNonce {
            rows.removeAll { $0.id.hasPrefix("local-") && $0.data.clientNonce == nonce }
        }
        if let index = rows.firstIndex(where: { $0.seq == entry.seq }) {
            if entry.rev < rows[index].rev { return }
            rows[index] = entry
        } else {
            rows.append(entry)
            rows.sort { $0.seq < $1.seq }
            if rows.count > 500 {
                rows.removeFirst(rows.count - 500)
            }
        }
        entriesByBot[entry.botId] = rows
        if entry.rev > rev { rev = entry.rev }
    }

    /// Merges a `history()` page (newest first) into the mirror.
    func mergeHistory(_ entries: [Entry]) {
        for entry in entries {
            upsertEntry(entry)
        }
    }

    /// Marks an optimistic local entry failed (send error) or sent.
    func updateLocalEntry(botId: String, clientNonce: String, status: String) {
        guard var rows = entriesByBot[botId],
              let index = rows.firstIndex(where: { $0.id == "local-\(clientNonce)" }) else { return }
        rows[index].data.status = status
        rows[index].updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        entriesByBot[botId] = rows
    }

    /// The optimistic local entry shown while `send` is in flight.
    func addLocalEntry(_ entry: Entry) {
        var rows = entriesByBot[entry.botId] ?? []
        rows.append(entry)
        entriesByBot[entry.botId] = rows
    }

    func removeLocalEntry(botId: String, clientNonce: String) {
        guard var rows = entriesByBot[botId] else { return }
        rows.removeAll { $0.id == "local-\(clientNonce)" }
        entriesByBot[botId] = rows
    }

    private func sortBots() {
        // Lead first, then pinned; otherwise keep host order (catch-up
        // order = roster order). Swift's sort is stable.
        bots.sort { lhs, rhs in
            if lhs.lead != rhs.lead { return lhs.lead }
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return false
        }
    }

    // MARK: - Persistence

    private func save() {
        let persisted = PersistedMirror(rev: rev, bots: bots)
        if let data = try? JSONEncoder().encode(persisted) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let persisted = try? JSONDecoder().decode(PersistedMirror.self, from: data) else {
            return
        }
        rev = persisted.rev
        bots = persisted.bots
        sortBots()
    }
}
