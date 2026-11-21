import Foundation
import SwiftUI

// MARK: - Feed

enum FeedFeedback: String, Codable {
    case none, up, down
}

struct FeedPost: Codable, Identifiable {
    var id = UUID()
    var title: String
    var body: String
    var category: String
    var createdAt: Date = Date()
    /// "chat" (saved from a chat reply) or "generated" (drafted from a routine).
    var source: String
    var feedback: FeedFeedback = .none
}

/// The Feed is the Muse-style briefing: posts the user (or their routine)
/// wrote into it. Nothing is pre-filled; a post only exists because the
/// user saved a chat reply or drafted one in the chat.
@MainActor
final class FeedStore: ObservableObject {
    static let key = "cn.lingyu.feedPosts"
    @Published private(set) var posts: [FeedPost] = []

    init() { load() }

    func add(title: String, body: String, category: String, source: String) {
        posts.insert(FeedPost(title: title, body: body, category: category, source: source), at: 0)
        save()
    }

    func setFeedback(id: UUID, feedback: FeedFeedback) {
        guard let index = posts.firstIndex(where: { $0.id == id }) else { return }
        posts[index].feedback = feedback
        save()
    }

    func remove(id: UUID) {
        posts.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([FeedPost].self, from: data) else { return }
        posts = decoded
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(posts), forKey: Self.key)
    }
}

// MARK: - Ideas

struct IdeaItem: Codable, Identifiable {
    var id = UUID()
    var title: String
    var category: String
    var createdAt: Date = Date()
    /// "chat" (saved from a chat reply) or "typed".
    var source: String
}

/// Ideas are suggestions the user saved from chat (or typed in directly).
/// Nothing is pre-filled.
@MainActor
final class IdeaStore: ObservableObject {
    static let key = "cn.lingyu.ideas"
    @Published private(set) var ideas: [IdeaItem] = []

    init() { load() }

    func add(title: String, category: String, source: String) {
        ideas.insert(IdeaItem(title: title, category: category, source: source), at: 0)
        save()
    }

    func remove(id: UUID) {
        ideas.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([IdeaItem].self, from: data) else { return }
        ideas = decoded
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(ideas), forKey: Self.key)
    }
}

// MARK: - Goals

/// Muse's seven goal categories.
enum GoalCategory: String, CaseIterable {
    case health, relationships, finance, career, interests, productivity, other

    var label: String {
        switch self {
        case .health: return L("健康")
        case .relationships: return L("人际")
        case .finance: return L("财务")
        case .career: return L("事业")
        case .interests: return L("兴趣")
        case .productivity: return L("效率")
        case .other: return L("其他")
        }
    }

    /// Map the old category values (from the earlier local goal list) to
    /// the Muse seven. Unmapped values fall back to "other". Old values
    /// were stored as raw values ("habit") or as labels ("习惯").
    static func migrated(_ old: String) -> String {
        switch old {
        case "health", "健康": return GoalCategory.health.rawValue
        case "finance", "财务": return GoalCategory.finance.rawValue
        case "habit", "习惯": return GoalCategory.productivity.rawValue
        case "learning", "学习": return GoalCategory.interests.rawValue
        case "project", "项目": return GoalCategory.career.rawValue
        case "travel", "旅行": return GoalCategory.interests.rawValue
        case "人际": return GoalCategory.relationships.rawValue
        case "事业": return GoalCategory.career.rawValue
        case "兴趣": return GoalCategory.interests.rawValue
        case "效率": return GoalCategory.productivity.rawValue
        default:
            return GoalCategory(rawValue: old)?.rawValue ?? GoalCategory.other.rawValue
        }
    }
}

struct GoalProgress: Codable, Identifiable {
    var id = UUID()
    var date: Date = Date()
    var text: String
}

struct GoalItem: Codable, Identifiable {
    var id = UUID()
    var title: String
    var type: String
    var progress: [GoalProgress] = []
    var completed: Bool = false
    var createdAt: Date = Date()
}

@MainActor
final class GoalStore: ObservableObject {
    static let key = "cn.lingyu.goals"
    @Published private(set) var goals: [GoalItem] = []

    init() { load() }

    func add(title: String, type: String) {
        goals.append(GoalItem(title: title, type: type))
        save()
    }

    func addProgress(goalId: UUID, text: String) {
        guard let index = goals.firstIndex(where: { $0.id == goalId }) else { return }
        goals[index].progress.append(GoalProgress(text: text))
        save()
    }

    func setCompleted(goalId: UUID, completed: Bool) {
        guard let index = goals.firstIndex(where: { $0.id == goalId }) else { return }
        goals[index].completed = completed
        save()
    }

    func remove(id: UUID) {
        goals.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([GoalItem].self, from: data) else { return }
        goals = decoded.map { goal in
            var g = goal
            g.type = GoalCategory.migrated(goal.type)
            return g
        }
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(goals), forKey: Self.key)
    }
}

// MARK: - Spaces

struct SpaceItem: Codable, Identifiable {
    var id = UUID()
    var title: String
    var description: String
    var createdAt: Date = Date()
}

/// Spaces are mini-tools the user asked an agent to build. A space starts
/// as a request ("待搭建") and is built through chat; nothing is pre-filled.
@MainActor
final class SpaceStore: ObservableObject {
    static let key = "cn.lingyu.spaces"
    @Published private(set) var spaces: [SpaceItem] = []

    init() { load() }

    func add(title: String, description: String) {
        spaces.append(SpaceItem(title: title, description: description))
        save()
    }

    func remove(id: UUID) {
        spaces.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key) else { return }
        if let decoded = try? JSONDecoder().decode([SpaceItem].self, from: data) {
            spaces = decoded
            return
        }
        // Old shape stored spaces as GoalItems; migrate the titles over.
        if let old = try? JSONDecoder().decode([GoalItem].self, from: data) {
            spaces = old.map { SpaceItem(title: $0.title, description: "") }
        }
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(spaces), forKey: Self.key)
    }
}
