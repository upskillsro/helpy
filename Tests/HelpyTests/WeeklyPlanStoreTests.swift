import XCTest
@testable import Helpy

final class WeeklyPlanStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "WeeklyPlanStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testUntouchedWeekIsEmpty() {
        let store = WeeklyPlanStore(defaults: defaults)
        XCTAssertEqual(store.plan(for: "2026-W35"), WeeklyPlan())
        XCTAssertFalse(store.hasPlan(for: "2026-W35"))
    }

    func testNotesRoundTripAndCountAsContent() {
        let store = WeeklyPlanStore(defaults: defaults)
        store.setNotes("Two calls moved to Friday", for: "2026-W35")
        XCTAssertTrue(store.hasPlan(for: "2026-W35"))

        let reloaded = WeeklyPlanStore(defaults: defaults)
        XCTAssertEqual(reloaded.plan(for: "2026-W35").notes, "Two calls moved to Friday")
    }

    /// A plan written before `notes` existed still has to load. The synthesised
    /// decoder throws on the missing key, and the store drops a week it cannot
    /// decode, so getting this wrong would delete the user's planning history.
    func testPlanWrittenBeforeNotesExistedStillLoads() {
        let stored = """
        {"2026-W35":{"goal":"Ship the planner","reward":"Sushi","tasks":\
        [{"id":"\(UUID().uuidString)","title":"Wire the grid","points":4,"isDone":false}]}}
        """
        defaults.set(Data(stored.utf8), forKey: "weeklyPlans_v1")

        let plan = WeeklyPlanStore(defaults: defaults).plan(for: "2026-W35")
        XCTAssertEqual(plan.goal, "Ship the planner")
        XCTAssertEqual(plan.reward, "Sushi")
        XCTAssertEqual(plan.notes, "")
        XCTAssertEqual(plan.tasks.map(\.title), ["Wire the grid"])
    }

    func testPlanRoundTripsAcrossLaunches() {
        let store = WeeklyPlanStore(defaults: defaults)
        store.setGoal("Ship the planner", for: "2026-W35")
        store.setReward("Sushi", for: "2026-W35")
        store.setLinkedList("list-1", for: "2026-W35")
        store.addTask(title: "Wire the grid", points: 4, reminderId: "rem-1", to: "2026-W35")

        let reloaded = WeeklyPlanStore(defaults: defaults)
        let plan = reloaded.plan(for: "2026-W35")
        XCTAssertEqual(plan.goal, "Ship the planner")
        XCTAssertEqual(plan.reward, "Sushi")
        XCTAssertEqual(plan.linkedListId, "list-1")
        XCTAssertEqual(plan.tasks.first?.reminderId, "rem-1")
        XCTAssertEqual(plan.tasks.map(\.title), ["Wire the grid"])
        XCTAssertEqual(plan.tasks.first?.points, 4)
    }

    func testEarnedPointsCountOnlyCheckedTasks() {
        let store = WeeklyPlanStore(defaults: defaults)
        store.addTask(title: "A", points: 3, to: "W")
        store.addTask(title: "B", points: 5, to: "W")
        XCTAssertEqual(store.plan(for: "W").earnedPoints, 0)

        let first = store.plan(for: "W").tasks[0].id
        store.toggleTask(id: first, in: "W")
        XCTAssertEqual(store.plan(for: "W").earnedPoints, 3)
        XCTAssertEqual(store.plan(for: "W").availablePoints, 8)
    }

    /// The target is the board, so the reward lands exactly when the last task
    /// does — there is no separate number that can disagree with the tasks.
    func testRewardIsEarnedWhenEveryTaskIsDone() {
        let store = WeeklyPlanStore(defaults: defaults)
        store.addTask(title: "A", points: 5, to: "W")
        store.addTask(title: "B", points: 3, to: "W")
        XCTAssertEqual(store.plan(for: "W").availablePoints, 8)
        XCTAssertFalse(store.plan(for: "W").isRewardEarned)

        store.toggleTask(id: store.plan(for: "W").tasks[0].id, in: "W")
        XCTAssertFalse(store.plan(for: "W").isRewardEarned, "half the board is not a win")

        store.toggleTask(id: store.plan(for: "W").tasks[1].id, in: "W")
        XCTAssertTrue(store.plan(for: "W").isRewardEarned)
        XCTAssertEqual(store.plan(for: "W").progress, 1)
    }

    func testEmptyWeekEarnsNothing() {
        let store = WeeklyPlanStore(defaults: defaults)
        store.setReward("Sushi", for: "W")
        XCTAssertFalse(store.plan(for: "W").isRewardEarned, "no tasks means nothing to earn")
        XCTAssertEqual(store.plan(for: "W").progress, 0)
    }

    func testPointsCanBeEditedAfterTheTaskIsAdded() {
        let store = WeeklyPlanStore(defaults: defaults)
        store.addTask(title: "A", points: 1, to: "W")
        let id = store.plan(for: "W").tasks[0].id

        store.updateTask(id: id, in: "W", points: 5)
        XCTAssertEqual(store.plan(for: "W").availablePoints, 5)

        store.updateTask(id: id, in: "W", title: "A renamed")
        XCTAssertEqual(store.plan(for: "W").tasks[0].title, "A renamed")

        // Points floor at zero rather than going negative on a stepper mash.
        store.updateTask(id: id, in: "W", points: -3)
        XCTAssertEqual(store.plan(for: "W").tasks[0].points, 0)
    }

    func testMirroredCompletionCanBePushedInFromReminders() {
        let store = WeeklyPlanStore(defaults: defaults)
        store.addTask(title: "A", points: 2, reminderId: "rem-1", to: "W")
        let id = store.plan(for: "W").tasks[0].id

        store.setTaskDone(true, id: id, in: "W")
        XCTAssertEqual(store.plan(for: "W").earnedPoints, 2)

        // A reminder the user deleted loses the link, never the score.
        store.setReminderId(nil, forTask: id, in: "W")
        XCTAssertNil(store.plan(for: "W").tasks[0].reminderId)
        XCTAssertEqual(store.plan(for: "W").earnedPoints, 2)
    }

    func testLinkingAWeekIsEnoughToKeepIt() {
        let store = WeeklyPlanStore(defaults: defaults)
        store.setLinkedList("list-1", for: "W")
        XCTAssertTrue(store.hasPlan(for: "W"))
        store.setLinkedList(nil, for: "W")
        XCTAssertFalse(store.hasPlan(for: "W"))
    }

    /// "Not chosen yet" and "switched off" have to stay distinguishable, or a
    /// default list silently re-links a week the user turned off.
    func testSwitchedOffIsNotTheSameAsUnset() {
        let store = WeeklyPlanStore(defaults: defaults)
        XCTAssertNil(store.plan(for: "W").linkedListId)
        XCTAssertFalse(store.plan(for: "W").isMirroringOff)

        store.setLinkedList(WeeklyPlan.noList, for: "W")
        XCTAssertTrue(store.plan(for: "W").isMirroringOff)
        XCTAssertTrue(store.hasPlan(for: "W"), "an off week must survive a reload")
    }

    func testBlankTaskTitleIsRejected() {
        let store = WeeklyPlanStore(defaults: defaults)
        store.addTask(title: "   ", points: 3, to: "W")
        XCTAssertTrue(store.plan(for: "W").tasks.isEmpty)
    }

    func testClearingAWeekForgetsIt() {
        let store = WeeklyPlanStore(defaults: defaults)
        store.setGoal("Something", for: "W")
        XCTAssertTrue(store.hasPlan(for: "W"))
        store.setGoal("", for: "W")
        XCTAssertFalse(store.hasPlan(for: "W"))
    }

    func testWeeksAreIndependent() {
        let store = WeeklyPlanStore(defaults: defaults)
        store.setGoal("This week", for: "2026-W35")
        store.setGoal("Next week", for: "2026-W36")
        XCTAssertEqual(store.plan(for: "2026-W35").goal, "This week")
        XCTAssertEqual(store.plan(for: "2026-W36").goal, "Next week")
    }

    /// One bad week must not cost the user their whole planning history.
    func testOneCorruptWeekDoesNotLoseTheOthers() throws {
        let good = #"{"goal":"Kept","reward":"","tasks":[]}"#
        let bad = #"{"goal":42,"tasks":"not an array"}"#
        let blob = "{\"2026-W35\":\(good),\"2026-W36\":\(bad)}"
        defaults.set(Data(blob.utf8), forKey: "weeklyPlans_v1")

        let store = WeeklyPlanStore(defaults: defaults)
        XCTAssertEqual(store.plan(for: "2026-W35").goal, "Kept")
        XCTAssertFalse(store.hasPlan(for: "2026-W36"))
    }

    func testUnreadableStoreStartsEmptyRatherThanCrashing() {
        defaults.set(Data("not json at all".utf8), forKey: "weeklyPlans_v1")
        let store = WeeklyPlanStore(defaults: defaults)
        XCTAssertFalse(store.hasPlan(for: "2026-W35"))
    }
}
