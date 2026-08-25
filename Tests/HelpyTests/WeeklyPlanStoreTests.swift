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

    func testPlanRoundTripsAcrossLaunches() {
        let store = WeeklyPlanStore(defaults: defaults)
        store.setGoal("Ship the planner", for: "2026-W35")
        store.setPointsTarget(10, for: "2026-W35")
        store.setReward("Sushi", for: "2026-W35")
        store.addTask(title: "Wire the grid", points: 4, to: "2026-W35")

        let reloaded = WeeklyPlanStore(defaults: defaults)
        let plan = reloaded.plan(for: "2026-W35")
        XCTAssertEqual(plan.goal, "Ship the planner")
        XCTAssertEqual(plan.pointsTarget, 10)
        XCTAssertEqual(plan.reward, "Sushi")
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

    func testRewardIsEarnedOnlyAtTarget() {
        let store = WeeklyPlanStore(defaults: defaults)
        store.setPointsTarget(5, for: "W")
        store.addTask(title: "A", points: 5, to: "W")
        XCTAssertFalse(store.plan(for: "W").isRewardEarned)

        store.toggleTask(id: store.plan(for: "W").tasks[0].id, in: "W")
        XCTAssertTrue(store.plan(for: "W").isRewardEarned)
    }

    func testZeroTargetNeverEarnsTheReward() {
        let store = WeeklyPlanStore(defaults: defaults)
        store.addTask(title: "A", points: 5, to: "W")
        store.toggleTask(id: store.plan(for: "W").tasks[0].id, in: "W")
        XCTAssertFalse(store.plan(for: "W").isRewardEarned, "no target means nothing to earn")
        XCTAssertEqual(store.plan(for: "W").progress, 0)
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
        let good = #"{"goal":"Kept","pointsTarget":3,"reward":"","tasks":[]}"#
        let bad = #"{"goal":42,"tasks":"not an array"}"#
        let blob = "{\"2026-W35\":\(good),\"2026-W36\":\(bad)}"
        defaults.set(Data(blob.utf8), forKey: "weeklyPlans_v1")

        let store = WeeklyPlanStore(defaults: defaults)
        XCTAssertEqual(store.plan(for: "2026-W35").goal, "Kept")
        XCTAssertEqual(store.plan(for: "2026-W35").pointsTarget, 3)
        XCTAssertFalse(store.hasPlan(for: "2026-W36"))
    }

    func testUnreadableStoreStartsEmptyRatherThanCrashing() {
        defaults.set(Data("not json at all".utf8), forKey: "weeklyPlans_v1")
        let store = WeeklyPlanStore(defaults: defaults)
        XCTAssertFalse(store.hasPlan(for: "2026-W35"))
    }
}
