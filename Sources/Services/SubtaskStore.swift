import Foundation
import SwiftUI

struct SubtaskItem: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var isCompleted: Bool = false
}

class SubtaskStore: ObservableObject {
    private let key = "subtasks_v1"
    private let defaults: UserDefaults
    @Published private var store: [String: [SubtaskItem]] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func subtasks(for taskId: String) -> [SubtaskItem] {
        store[taskId] ?? []
    }

    /// (completed, total) — (0, 0) when the task has no subtasks.
    func progress(for taskId: String) -> (done: Int, total: Int) {
        let items = store[taskId] ?? []
        return (items.filter(\.isCompleted).count, items.count)
    }

    func hasSubtasks(for taskId: String) -> Bool {
        !(store[taskId]?.isEmpty ?? true)
    }

    func addSubtask(title: String, for taskId: String) {
        var items = store[taskId] ?? []
        items.append(SubtaskItem(title: title))
        store[taskId] = items
        save()
    }

    func toggleSubtask(id: UUID, for taskId: String) {
        guard var items = store[taskId],
              let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].isCompleted.toggle()
        store[taskId] = items
        save()
    }

    func deleteSubtask(id: UUID, for taskId: String) {
        guard var items = store[taskId] else { return }
        items.removeAll { $0.id == id }
        store[taskId] = items
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(store) else { return }
        defaults.set(data, forKey: key)
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: [SubtaskItem]].self, from: data)
        else { return }
        store = decoded
    }
}
