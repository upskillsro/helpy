import XCTest
@testable import Helpy

final class RoadmapStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "RoadmapStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testUntouchedRoadmapIsEmpty() {
        XCTAssertTrue(RoadmapStore(defaults: defaults).roadmap.isEmpty)
    }

    func testRoadmapRoundTripsAcrossLaunches() {
        let store = RoadmapStore(defaults: defaults)
        store.setGoal("Ship Helpy 1.0")
        store.setNotes("Paying users, not downloads.")
        let milestone = store.addMilestone(title: "Beta")!
        store.addTask(title: "Fix the board", to: milestone.id)

        let reloaded = RoadmapStore(defaults: defaults).roadmap
        XCTAssertEqual(reloaded.goal, "Ship Helpy 1.0")
        XCTAssertEqual(reloaded.notes, "Paying users, not downloads.")
        XCTAssertEqual(reloaded.milestones.map(\.title), ["Beta"])
        XCTAssertEqual(reloaded.milestones[0].tasks.map(\.title), ["Fix the board"])
    }

    func testBlankTitlesAreRejected() {
        let store = RoadmapStore(defaults: defaults)
        XCTAssertNil(store.addMilestone(title: "   "))
        let milestone = store.addMilestone(title: "Beta")!
        XCTAssertNil(store.addTask(title: "\n", to: milestone.id))
        XCTAssertTrue(store.roadmap.milestones[0].tasks.isEmpty)
    }

    /// The two levels must never disagree on screen: a milestone cannot read
    /// as done while a step under it is open.
    func testMilestoneIsDoneOnlyWhenEveryStepIs() {
        let store = RoadmapStore(defaults: defaults)
        let milestone = store.addMilestone(title: "Beta")!
        let a = store.addTask(title: "A", to: milestone.id)!
        let b = store.addTask(title: "B", to: milestone.id)!

        XCTAssertFalse(store.roadmap.milestones[0].isComplete)
        store.toggleTask(a.id, in: milestone.id)
        XCTAssertFalse(store.roadmap.milestones[0].isComplete)
        store.toggleTask(b.id, in: milestone.id)
        XCTAssertTrue(store.roadmap.milestones[0].isComplete)
    }

    func testTickingAMilestoneTicksItsSteps() {
        let store = RoadmapStore(defaults: defaults)
        let milestone = store.addMilestone(title: "Beta")!
        store.addTask(title: "A", to: milestone.id)
        store.addTask(title: "B", to: milestone.id)

        store.toggleMilestone(milestone.id)
        XCTAssertTrue(store.roadmap.milestones[0].tasks.allSatisfy(\.isDone))

        store.toggleMilestone(milestone.id)
        XCTAssertTrue(store.roadmap.milestones[0].tasks.allSatisfy { !$0.isDone })
    }

    func testAMilestoneWithNoStepsCanStillBeTicked() {
        let store = RoadmapStore(defaults: defaults)
        let milestone = store.addMilestone(title: "Register the company")!
        store.toggleMilestone(milestone.id)
        XCTAssertTrue(store.roadmap.milestones[0].isComplete)
    }

    /// Adding work to something already finished reopens it, rather than
    /// leaving a "done" milestone with an untouched step inside.
    func testANewStepReopensAFinishedMilestone() {
        let store = RoadmapStore(defaults: defaults)
        let milestone = store.addMilestone(title: "Beta")!
        store.toggleMilestone(milestone.id)
        XCTAssertTrue(store.roadmap.milestones[0].isComplete)

        store.addTask(title: "One more thing", to: milestone.id)
        XCTAssertFalse(store.roadmap.milestones[0].isComplete)
    }

    /// Milestones weigh the same however many steps they carry, so one large
    /// milestone cannot swamp the whole roadmap.
    func testProgressIsWeightedByMilestone() {
        let store = RoadmapStore(defaults: defaults)
        let small = store.addMilestone(title: "Small")!
        let big = store.addMilestone(title: "Big")!
        store.toggleMilestone(small.id)
        for index in 0..<10 { store.addTask(title: "step \(index)", to: big.id) }

        XCTAssertEqual(store.roadmap.progress, 0.5, accuracy: 0.0001)
        XCTAssertEqual(store.roadmap.doneMilestones, 1)
    }

    func testDeletingAMilestoneTakesItsStepsWithIt() {
        let store = RoadmapStore(defaults: defaults)
        let milestone = store.addMilestone(title: "Beta")!
        store.addTask(title: "A", to: milestone.id)
        store.deleteMilestone(milestone.id)
        XCTAssertTrue(store.roadmap.milestones.isEmpty)
        XCTAssertTrue(store.roadmap.isEmpty)
    }

    func testUnreadableStoreStartsEmptyRatherThanCrashing() {
        defaults.set(Data("not json at all".utf8), forKey: "roadmap_v1")
        XCTAssertTrue(RoadmapStore(defaults: defaults).roadmap.isEmpty)
    }
}
