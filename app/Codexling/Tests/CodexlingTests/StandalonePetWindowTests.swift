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

    func testExpandedVerticalWidthIsFixed() {
        let small = StandalonePetLayout.expandedSize(edge: .bottom, scale: 0.8, taskCount: 2)
        let big = StandalonePetLayout.expandedSize(edge: .bottom, scale: 1.25, taskCount: 2)
        XCTAssertEqual(small.width, big.width, "展开态任务栈宽度不随 scale 变化")
        XCTAssertEqual(small.width, StandalonePetLayout.expandedVerticalWidth)
    }

    func testScaleOnlyChangesPetHeightInExpanded() {
        let small = StandalonePetLayout.expandedSize(edge: .bottom, scale: 0.8, taskCount: 4)
        let big = StandalonePetLayout.expandedSize(edge: .bottom, scale: 1.25, taskCount: 4)
        let heightDelta = big.height - small.height
        let petDelta = StandalonePetLayout.petDisplayHeight(scale: 1.25) - StandalonePetLayout.petDisplayHeight(scale: 0.8)
        XCTAssertEqual(heightDelta, petDelta, accuracy: 0.001, "展开态高度增量应只等于 Pet 的高度增量")
    }

    func testStackHeightCapsAtFourRows() {
        let one = StandalonePetLayout.stackHeight(taskCount: 1)
        let four = StandalonePetLayout.stackHeight(taskCount: 4)
        let many = StandalonePetLayout.stackHeight(taskCount: 9)
        XCTAssertGreaterThan(four, one)
        XCTAssertEqual(many, four, "超过 4 条应保持 4 条高度，内部滚动")
        XCTAssertEqual(StandalonePetLayout.stackHeight(taskCount: 0), 84)
    }

    func testExpandedVerticalHeightGrowsWithTaskCount() {
        let one = StandalonePetLayout.expandedSize(edge: .bottom, scale: 1.0, taskCount: 1).height
        let four = StandalonePetLayout.expandedSize(edge: .bottom, scale: 1.0, taskCount: 4).height
        let many = StandalonePetLayout.expandedSize(edge: .bottom, scale: 1.0, taskCount: 9).height
        XCTAssertGreaterThan(four, one)
        XCTAssertEqual(many, four)
    }

    func testToggleExpanded() {
        let model = StandalonePetViewModel()
        model.toggleExpanded()
        XCTAssertTrue(model.isExpanded)
        model.toggleExpanded()
        XCTAssertFalse(model.isExpanded)
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
