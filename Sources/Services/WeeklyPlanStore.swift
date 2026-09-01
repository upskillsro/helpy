import Foundation
import SwiftUI

/// One scored item in a week's plan.
///
/// When the week is linked to a Reminders list, adding one of these also
/// creates a real reminder due inside that week — that is what puts it in the
/// list board's "This week" column — and `reminderId` is the thread back to it.
/// Unlinked weeks keep working exactly as before, entirely inside Helpy.
struct WeeklyPlanTask: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var points: Int = 1
    var isDone: Bool = false
    /// `calendarItemIdentifier` of the mirrored reminder, if there is one.
    var reminderId: String?
}

struct WeeklyPlan: Codable, Equatable {
    var goal: String = ""
    var reward: String = ""
    /// Free text for the week. Not scored, not mirrored — the place for the
    /// context a task title cannot carry.
    var notes: String = ""
    var tasks: [WeeklyPlanTask] = []
    /// Reminders list this week mirrors into. nil means "not chosen yet", so
    /// the week follows whatever the default list is; `noList` means the user
    /// switched mirroring off for this week specifically.
    var linkedListId: String?

    /// Stored in `linkedListId` to mean "off", as distinct from "unset".
    static let noList = ""

    var earnedPoints: Int { tasks.filter(\.isDone).map(\.points).reduce(0, +) }

    /// The target. There is no separate number to keep in sync: the week is
    /// won when everything on it is done, so the target IS the total on the
    /// board. A target the user could set independently of the tasks was just
    /// a second place for the same fact to be wrong.
    var availablePoints: Int { tasks.map(\.points).reduce(0, +) }

    var doneCount: Int { tasks.filter(\.isDone).count }

    /// A week the user has not touched. Nothing is written for it, so the store
    /// stays small and the rolling window needs no backfill.
    var isEmpty: Bool {
        goal.isEmpty && reward.isEmpty && notes.isEmpty && tasks.isEmpty && linkedListId == nil
    }

    /// A week the user has switched off. Kept so the default cannot re-link it.
    var isMirroringOff: Bool { linkedListId == Self.noList }

    var isRewardEarned: Bool {
        availablePoints > 0 && earnedPoints >= availablePoints
    }

    var progress: Double {
        guard availablePoints > 0 else { return 0 }
        return min(1, Double(earnedPoints) / Double(availablePoints))
    }

    init() {}

    /// Every key is optional on the way in. Swift's synthesised decoder throws
    /// `keyNotFound` for a property a stored plan predates — and the store
    /// drops a week it cannot decode — so adding a field the synthesised way
    /// would quietly delete every plan written before it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        goal = try container.decodeIfPresent(String.self, forKey: .goal) ?? ""
        reward = try container.decodeIfPresent(String.self, forKey: .reward) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        tasks = try container.decodeIfPresent([WeeklyPlanTask].self, forKey: .tasks) ?? []
        linkedListId = try container.decodeIfPresent(String.self, forKey: .linkedListId)
    }
}

/// Weekly plans, keyed by week ("2026-W35"). Follows `SubtaskStore`: one JSON
/// blob in `UserDefaults`, decoded on init, written on every mutation.
///
/// Decoding is per-week rather than whole-store: one unreadable week comes back
/// empty instead of taking every other week down with it.
final class WeeklyPlanStore: ObservableObject {
    private let key = "weeklyPlans_v1"
    private let defaults: UserDefaults
    @Published private var plans: [String: WeeklyPlan] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func plan(for weekId: String) -> WeeklyPlan {
        plans[weekId] ?? WeeklyPlan()
    }

    func hasPlan(for weekId: String) -> Bool {
        !(plans[weekId]?.isEmpty ?? true)
    }

    /// Single write path. An emptied week is removed rather than stored blank,
    /// so `hasPlan` never reports a week the user has cleared out.
    func update(_ weekId: String, _ mutate: (inout WeeklyPlan) -> Void) {
        var plan = plans[weekId] ?? WeeklyPlan()
        mutate(&plan)
        if plan.isEmpty {
            plans.removeValue(forKey: weekId)
        } else {
            plans[weekId] = plan
        }
        save()
    }

    func setGoal(_ goal: String, for weekId: String) {
        update(weekId) { $0.goal = goal }
    }

    func setReward(_ reward: String, for weekId: String) {
        update(weekId) { $0.reward = reward }
    }

    func setNotes(_ notes: String, for weekId: String) {
        update(weekId) { $0.notes = notes }
    }

    func setLinkedList(_ listId: String?, for weekId: String) {
        update(weekId) { $0.linkedListId = listId }
    }

    @discardableResult
    func addTask(title: String, points: Int, reminderId: String? = nil, to weekId: String) -> WeeklyPlanTask? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let task = WeeklyPlanTask(title: trimmed, points: max(0, points), reminderId: reminderId)
        update(weekId) { $0.tasks.append(task) }
        return task
    }

    func toggleTask(id: UUID, in weekId: String) {
        update(weekId) { plan in
            guard let index = plan.tasks.firstIndex(where: { $0.id == id }) else { return }
            plan.tasks[index].isDone.toggle()
        }
    }

    /// Used by the Reminders mirror when the truth changed on the other side.
    func setTaskDone(_ isDone: Bool, id: UUID, in weekId: String) {
        update(weekId) { plan in
            guard let index = plan.tasks.firstIndex(where: { $0.id == id }),
                  plan.tasks[index].isDone != isDone else { return }
            plan.tasks[index].isDone = isDone
        }
    }

    func setReminderId(_ reminderId: String?, forTask id: UUID, in weekId: String) {
        update(weekId) { plan in
            guard let index = plan.tasks.firstIndex(where: { $0.id == id }) else { return }
            plan.tasks[index].reminderId = reminderId
        }
    }

    func updateTask(id: UUID, in weekId: String, title: String? = nil, points: Int? = nil) {
        update(weekId) { plan in
            guard let index = plan.tasks.firstIndex(where: { $0.id == id }) else { return }
            if let title {
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { plan.tasks[index].title = trimmed }
            }
            if let points { plan.tasks[index].points = max(0, points) }
        }
    }

    func deleteTask(id: UUID, in weekId: String) {
        update(weekId) { $0.tasks.removeAll { $0.id == id } }
    }

    func moveTasks(in weekId: String, from source: IndexSet, to destination: Int) {
        update(weekId) { $0.tasks.move(fromOffsets: source, toOffset: destination) }
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(plans) else { return }
        defaults.set(data, forKey: key)
    }

    /// Decodes week by week. A corrupt entry is dropped and logged; the rest of
    /// the user's planning history survives.
    private func load() {
        guard let data = defaults.data(forKey: key) else { return }

        if let decoded = try? JSONDecoder().decode([String: WeeklyPlan].self, from: data) {
            plans = decoded
            return
        }

        guard let raw = try? JSONDecoder().decode([String: JSONValue].self, from: data) else {
            AppLogger.ui.error("weeklyPlans_v1 is unreadable; starting empty")
            return
        }

        var recovered: [String: WeeklyPlan] = [:]
        for (weekId, value) in raw {
            guard let blob = try? JSONEncoder().encode(value),
                  let plan = try? JSONDecoder().decode(WeeklyPlan.self, from: blob) else {
                AppLogger.ui.error("Dropping unreadable weekly plan \(weekId, privacy: .public)")
                continue
            }
            recovered[weekId] = plan
        }
        plans = recovered
    }
}

/// Minimal any-JSON box, used only to salvage the good weeks out of a store
/// where one week failed to decode.
private enum JSONValue: Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
