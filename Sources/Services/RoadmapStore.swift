import Foundation
import SwiftUI

/// A step under a milestone. The second level of the roadmap checklist.
struct RoadmapTask: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var isDone: Bool = false
}

/// The first level of the roadmap checklist: a milestone and the steps that get
/// you there.
struct RoadmapMilestone: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var tasks: [RoadmapTask] = []
    /// Only consulted for a milestone with no steps under it. Once it has
    /// steps they are the truth, so a milestone can never claim to be done
    /// while something under it is not.
    var isDone: Bool = false

    var doneCount: Int { tasks.filter(\.isDone).count }

    var isComplete: Bool { tasks.isEmpty ? isDone : doneCount == tasks.count }

    var progress: Double {
        guard !tasks.isEmpty else { return isDone ? 1 : 0 }
        return Double(doneCount) / Double(tasks.count)
    }
}

/// The long game: one goal, the thinking behind it, and the milestones that get
/// there. Weeks are how you spend your time; this is what you are spending it
/// on, which is why it sits beside them rather than inside one.
struct Roadmap: Codable, Equatable {
    var goal: String = ""
    var notes: String = ""
    var milestones: [RoadmapMilestone] = []

    var isEmpty: Bool { goal.isEmpty && notes.isEmpty && milestones.isEmpty }

    var doneMilestones: Int { milestones.filter(\.isComplete).count }

    /// Weighted by milestone, not by step: five milestones of one step each and
    /// one milestone of fifty steps should not make the fifty-step one worth
    /// ten times the rest of the roadmap put together.
    var progress: Double {
        guard !milestones.isEmpty else { return 0 }
        return milestones.map(\.progress).reduce(0, +) / Double(milestones.count)
    }
}

/// The roadmap, as one JSON blob in `UserDefaults`. Same shape as
/// `WeeklyPlanStore`: decoded on init, written on every mutation.
///
/// There is exactly one roadmap. Making it a list of roadmaps would be the
/// obvious generalisation and the wrong one — the point of the column is that
/// there is a single thing everything else is in service of.
final class RoadmapStore: ObservableObject {
    private let key = "roadmap_v1"
    private let defaults: UserDefaults

    @Published private(set) var roadmap = Roadmap()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Roadmap.self, from: data) {
            roadmap = decoded
        } else if defaults.data(forKey: key) != nil {
            AppLogger.ui.error("roadmap_v1 is unreadable; starting empty")
        }
    }

    // MARK: - The headline

    func setGoal(_ goal: String) { update { $0.goal = goal } }

    func setNotes(_ notes: String) { update { $0.notes = notes } }

    // MARK: - Milestones

    @discardableResult
    func addMilestone(title: String) -> RoadmapMilestone? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let milestone = RoadmapMilestone(title: trimmed)
        update { $0.milestones.append(milestone) }
        return milestone
    }

    func renameMilestone(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update { road in
            guard let index = road.milestones.firstIndex(where: { $0.id == id }) else { return }
            road.milestones[index].title = trimmed
        }
    }

    func deleteMilestone(_ id: UUID) {
        update { $0.milestones.removeAll { $0.id == id } }
    }

    /// Ticking a milestone ticks everything under it, and unticking clears them
    /// all. Anything else leaves the two levels disagreeing on screen.
    func toggleMilestone(_ id: UUID) {
        update { road in
            guard let index = road.milestones.firstIndex(where: { $0.id == id }) else { return }
            let target = !road.milestones[index].isComplete
            road.milestones[index].isDone = target
            for task in road.milestones[index].tasks.indices {
                road.milestones[index].tasks[task].isDone = target
            }
        }
    }

    func moveMilestones(from source: IndexSet, to destination: Int) {
        update { $0.milestones.move(fromOffsets: source, toOffset: destination) }
    }

    // MARK: - Steps

    @discardableResult
    func addTask(title: String, to milestoneId: UUID) -> RoadmapTask? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let task = RoadmapTask(title: trimmed)
        update { road in
            guard let index = road.milestones.firstIndex(where: { $0.id == milestoneId }) else { return }
            road.milestones[index].tasks.append(task)
            // A finished milestone that just grew a new step is not finished.
            road.milestones[index].isDone = false
        }
        return task
    }

    func renameTask(_ id: UUID, in milestoneId: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutateTask(id, in: milestoneId) { $0.title = trimmed }
    }

    func toggleTask(_ id: UUID, in milestoneId: UUID) {
        mutateTask(id, in: milestoneId) { $0.isDone.toggle() }
    }

    func deleteTask(_ id: UUID, in milestoneId: UUID) {
        update { road in
            guard let index = road.milestones.firstIndex(where: { $0.id == milestoneId }) else { return }
            road.milestones[index].tasks.removeAll { $0.id == id }
        }
    }

    func moveTasks(in milestoneId: UUID, from source: IndexSet, to destination: Int) {
        update { road in
            guard let index = road.milestones.firstIndex(where: { $0.id == milestoneId }) else { return }
            road.milestones[index].tasks.move(fromOffsets: source, toOffset: destination)
        }
    }

    // MARK: - Persistence

    private func mutateTask(_ id: UUID, in milestoneId: UUID, _ mutate: (inout RoadmapTask) -> Void) {
        update { road in
            guard let m = road.milestones.firstIndex(where: { $0.id == milestoneId }),
                  let t = road.milestones[m].tasks.firstIndex(where: { $0.id == id }) else { return }
            mutate(&road.milestones[m].tasks[t])
        }
    }

    /// Single write path.
    private func update(_ mutate: (inout Roadmap) -> Void) {
        var next = roadmap
        mutate(&next)
        guard next != roadmap else { return }
        roadmap = next
        if next.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: key)
        }
    }
}
