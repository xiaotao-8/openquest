import Foundation
import SwiftUI

/// The routines cache: one `RoutineListing` per bot, fetched from the host
/// after connect and refreshed when a routine-related entry arrives or
/// after any mutation. Never invented: a bot with no listing yet simply
/// shows no routines, and a failed fetch keeps the last good listing and
/// records the error for the view to show.
@MainActor
final class RoutineStore: ObservableObject {
    @Published private(set) var listings: [String: RoutineListing] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private var refreshing: Set<String> = []
    private var lastRefresh: [String: Date] = [:]
    /// Minimum gap between unforced refreshes of one bot, so an entry
    /// burst does not turn into an RPC burst.
    private static let throttle: TimeInterval = 10

    // MARK: - Lookups

    func listing(botId: String) -> RoutineListing? {
        listings[botId]
    }

    func routine(botId: String, routineId: String) -> Routine? {
        listings[botId]?.routines.first { $0.id == routineId }
    }

    /// Every routine across bots, soonest next run first (no next run
    /// sorts last, then by name).
    var allRoutines: [(botId: String, routine: Routine)] {
        let all = listings.flatMap { (botId, listing) in
            listing.routines.map { (botId: botId, routine: $0) }
        }
        return all.sorted { lhs, rhs in
            switch (lhs.routine.nextRunAt, rhs.routine.nextRunAt) {
            case (nil, nil): return lhs.routine.name < rhs.routine.name
            case (nil, _): return false
            case (_, nil): return true
            case (let a?, let b?): return a != b ? a < b : lhs.routine.name < rhs.routine.name
            }
        }
    }

    var routineCount: Int {
        listings.values.reduce(0) { $0 + $1.routines.count }
    }

    /// The soonest upcoming run across bots, if any routine has one.
    var nextRun: (botId: String, routine: Routine, at: Int64)? {
        allRoutines.compactMap { item -> (botId: String, routine: Routine, at: Int64)? in
            guard let at = item.routine.nextRunAt else { return nil }
            return (botId: item.botId, routine: item.routine, at: at)
        }.first
    }

    /// Every run across bots, newest first.
    var allRuns: [(botId: String, run: RoutineRun)] {
        let all = listings.flatMap { (botId, listing) in
            listing.runs.map { (botId: botId, run: $0) }
        }
        return all.sorted { $0.run.createdAt > $1.run.createdAt }
    }

    /// Runs of one routine, newest first.
    func runs(for routineId: String) -> [(botId: String, run: RoutineRun)] {
        allRuns.filter { $0.run.routineId == routineId }
    }

    /// Every waiting follow-up across bots, soonest due first.
    var allFollowUps: [(botId: String, followUp: FollowUp)] {
        let all = listings.flatMap { (botId, listing) in
            (listing.followUps ?? []).map { (botId: botId, followUp: $0) }
        }
        return all.sorted { $0.followUp.at < $1.followUp.at }
    }

    // MARK: - Fetching

    func refreshAll(api: HostAPI, botIds: [String], force: Bool = false) async {
        for botId in botIds {
            await refresh(botId: botId, api: api, force: force)
        }
    }

    func refresh(botId: String, api: HostAPI, force: Bool = false) async {
        if refreshing.contains(botId) { return }
        if !force, let last = lastRefresh[botId],
           Date().timeIntervalSince(last) < Self.throttle {
            return
        }
        refreshing.insert(botId)
        defer { refreshing.remove(botId) }
        isLoading = true
        defer { isLoading = false }
        do {
            listings[botId] = try await api.routines(botId: botId)
            lastRefresh[botId] = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Mutations (each re-reads the bot's listing afterwards)

    /// Saves a routine (create when `routineId` is nil) and returns the
    /// saved row. Throws the host's error so the editor can show it.
    func save(botId: String, routineId: String?, name: String, instruction: String,
              triggers: [RoutineTrigger], timeoutSeconds: Int, api: HostAPI) async throws -> Routine {
        let saved = try await api.saveRoutine(
            botId: botId, id: routineId, name: name, instruction: instruction,
            triggers: triggers, timeoutSeconds: timeoutSeconds)
        await refresh(botId: botId, api: api, force: true)
        return saved
    }

    func setEnabled(botId: String, routineId: String, enabled: Bool, api: HostAPI) async -> Bool {
        do {
            try await api.setRoutineEnabled(botId: botId, id: routineId, enabled: enabled)
            await refresh(botId: botId, api: api, force: true)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func delete(botId: String, routineId: String, api: HostAPI) async -> Bool {
        do {
            try await api.deleteRoutine(botId: botId, id: routineId)
            await refresh(botId: botId, api: api, force: true)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func retryRun(botId: String, runId: String, api: HostAPI) async -> Bool {
        do {
            try await api.retryRoutineRun(botId: botId, runId: runId)
            await refresh(botId: botId, api: api, force: true)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func cancelFollowUp(botId: String, followUpId: String, api: HostAPI) async -> Bool {
        do {
            try await api.cancelFollowUp(botId: botId, id: followUpId)
            await refresh(botId: botId, api: api, force: true)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Preview / lifecycle

    /// Preview-only injection: seeded demo listings for screenshots
    /// (never from the host).
    func seedDemo(botId: String, listing: RoutineListing) {
        listings[botId] = listing
    }

    /// Drops every listing (on disconnect: a stale list must not pose as
    /// live data).
    func clear() {
        listings = [:]
        lastError = nil
    }
}
