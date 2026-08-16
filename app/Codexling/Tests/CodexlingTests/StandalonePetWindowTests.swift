import XCTest
@testable import Codexling

@MainActor
final class StandalonePetWindowTests: XCTestCase {
    func testCollapsedSizeScalesPet() {
        let one = StandalonePetLayout.collapsedSize(scale: 1.0)
        let big = StandalonePetLayout.collapsedSize(scale: 1.25)
        XCTAssertGreaterThan(big.width, one.width)
        XCTAssertGreaterThan(big.height, one.height)
    }

    func testTaskPanelWidthIsFixed() {
        let size = StandalonePetLayout.taskPanelSize(taskCount: 2)
        XCTAssertEqual(size.width, StandalonePetLayout.taskPanelWidth)
    }

    func testTaskPanelHeightGrowsWithTaskCount() {
        let one = StandalonePetLayout.taskPanelSize(taskCount: 1)
        let four = StandalonePetLayout.taskPanelSize(taskCount: 4)
        let many = StandalonePetLayout.taskPanelSize(taskCount: 9)
        XCTAssertGreaterThan(four.height, one.height)
        XCTAssertEqual(many.height, four.height, "超过 4 条应保持 4 条高度，内部滚动")
    }

    func testStackHeightCapsAtFourRows() {
        let one = StandalonePetLayout.stackHeight(taskCount: 1)
        let four = StandalonePetLayout.stackHeight(taskCount: 4)
        let many = StandalonePetLayout.stackHeight(taskCount: 9)
        XCTAssertGreaterThan(four, one)
        XCTAssertEqual(many, four)
        XCTAssertEqual(StandalonePetLayout.stackHeight(taskCount: 0), 84)
    }

    func testToggleExpanded() {
        let model = StandalonePetViewModel()
        model.toggleExpanded()
        XCTAssertTrue(model.isExpanded)
        model.toggleExpanded()
        XCTAssertFalse(model.isExpanded)
    }

    func testTaskCountDidChange() {
        let model = StandalonePetViewModel()
        var received: Int?
        model.onTaskCountChanged = { received = $0 }
        model.taskCountDidChange(3)
        XCTAssertEqual(model.taskCount, 3)
        XCTAssertEqual(received, 3)
    }

    func testEdgeChangeNotifiesAndClearsFreeOrigin() {
        let model = StandalonePetViewModel()
        model.freeOrigin = NSPoint(x: 100, y: 200)
        var received: StandalonePetEdge?
        model.onEdgeChange = { received = $0 }
        model.setEdge(.right)
        XCTAssertEqual(model.edge, .right)
        XCTAssertEqual(received, .right)
        XCTAssertNil(model.freeOrigin)
    }

    func testEffectiveEdgeIsBottomWhenFreeFloating() {
        let model = StandalonePetViewModel()
        model.edge = .left
        XCTAssertEqual(model.effectiveEdge, .left)
        model.freeOrigin = NSPoint(x: 0, y: 0)
        XCTAssertEqual(model.effectiveEdge, .bottom)
    }
}
