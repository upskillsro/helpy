import XCTest
@testable import Helpy

final class SubtaskStoreTests: XCTestCase {
    private var store: SubtaskStore!
    private let taskId = "test-task-abc"
    private let testDefaults = UserDefaults(suiteName: "com.helpy.subtask-tests")!

    override func setUp() {
        super.setUp()
        testDefaults.removePersistentDomain(forName: "com.helpy.subtask-tests")
        store = SubtaskStore(defaults: testDefaults)
    }

    func testAddSubtask() {
        store.addSubtask(title: "Do the thing", for: taskId)
        let items = store.subtasks(for: taskId)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Do the thing")
        XCTAssertFalse(items[0].isCompleted)
    }

    func testToggleSubtaskCompletion() {
        store.addSubtask(title: "Do the thing", for: taskId)
        let id = store.subtasks(for: taskId)[0].id
        store.toggleSubtask(id: id, for: taskId)
        XCTAssertTrue(store.subtasks(for: taskId)[0].isCompleted)
        store.toggleSubtask(id: id, for: taskId)
        XCTAssertFalse(store.subtasks(for: taskId)[0].isCompleted)
    }

    func testDeleteSubtask() {
        store.addSubtask(title: "Do the thing", for: taskId)
        let id = store.subtasks(for: taskId)[0].id
        store.deleteSubtask(id: id, for: taskId)
        XCTAssertEqual(store.subtasks(for: taskId).count, 0)
    }

    func testSubtasksForUnknownTaskAreEmpty() {
        XCTAssertEqual(store.subtasks(for: "no-such-task").count, 0)
    }

    func testMultipleTasksAreIsolated() {
        store.addSubtask(title: "Task A subtask", for: "task-a")
        store.addSubtask(title: "Task B subtask", for: "task-b")
        XCTAssertEqual(store.subtasks(for: "task-a").count, 1)
        XCTAssertEqual(store.subtasks(for: "task-b").count, 1)
        XCTAssertEqual(store.subtasks(for: "task-a")[0].title, "Task A subtask")
    }

    func testPersistence() {
        store.addSubtask(title: "Persisted", for: taskId)
        let store2 = SubtaskStore(defaults: testDefaults)
        XCTAssertEqual(store2.subtasks(for: taskId).count, 1)
        XCTAssertEqual(store2.subtasks(for: taskId)[0].title, "Persisted")
    }

    func testProgressCountsCompleted() {
        store.addSubtask(title: "One", for: taskId)
        store.addSubtask(title: "Two", for: taskId)
        store.addSubtask(title: "Three", for: taskId)
        let firstId = store.subtasks(for: taskId)[0].id
        store.toggleSubtask(id: firstId, for: taskId)

        let progress = store.progress(for: taskId)
        XCTAssertEqual(progress.done, 1)
        XCTAssertEqual(progress.total, 3)
    }

    func testProgressForUnknownTaskIsZero() {
        let progress = store.progress(for: "no-such-task")
        XCTAssertEqual(progress.done, 0)
        XCTAssertEqual(progress.total, 0)
    }

    func testHasSubtasks() {
        XCTAssertFalse(store.hasSubtasks(for: taskId))
        store.addSubtask(title: "One", for: taskId)
        XCTAssertTrue(store.hasSubtasks(for: taskId))
        let id = store.subtasks(for: taskId)[0].id
        store.deleteSubtask(id: id, for: taskId)
        XCTAssertFalse(store.hasSubtasks(for: taskId))
    }
}
