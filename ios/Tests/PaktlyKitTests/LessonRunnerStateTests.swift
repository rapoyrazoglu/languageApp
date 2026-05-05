import XCTest
@testable import PaktlyKit

@MainActor
final class LessonRunnerStateTests: XCTestCase {

    private func lesson(blockCount: Int) -> Lesson {
        let blocks = (0..<blockCount).map { i in
            Block.explanation(ExplanationBlock(text: "block \(i)"))
        }
        return Lesson(id: "L", title: "T", blocks: blocks)
    }

    func testInit_StartsAtFirstBlock() {
        let state = LessonRunnerState(lesson: lesson(blockCount: 3))
        XCTAssertEqual(state.index, 0)
        XCTAssertFalse(state.isComplete)
        XCTAssertTrue(state.canAdvance)
        XCTAssertFalse(state.canGoBack)
        XCTAssertEqual(state.progress, 0.0)
    }

    func testEmpty_LessonIsImmediatelyComplete() {
        let state = LessonRunnerState(lesson: lesson(blockCount: 0))
        XCTAssertTrue(state.isEmpty)
        XCTAssertTrue(state.isComplete)
        XCTAssertEqual(state.progress, 1.0)
        XCTAssertNil(state.currentBlock)
        XCTAssertFalse(state.canAdvance)
        XCTAssertFalse(state.canGoBack)
    }

    func testAdvance_StopsAtCompletionState() {
        let state = LessonRunnerState(lesson: lesson(blockCount: 2))

        state.advance()
        XCTAssertEqual(state.index, 1)
        XCTAssertNotNil(state.currentBlock)
        XCTAssertEqual(state.progress, 0.5)

        state.advance()
        XCTAssertEqual(state.index, 2)
        XCTAssertTrue(state.isComplete)
        XCTAssertNil(state.currentBlock)
        XCTAssertEqual(state.progress, 1.0)

        // Past completion, advance is a no-op.
        state.advance()
        XCTAssertEqual(state.index, 2)
    }

    func testGoBack_StopsAtZero() {
        let state = LessonRunnerState(lesson: lesson(blockCount: 3))
        state.advance()
        state.advance()
        XCTAssertEqual(state.index, 2)

        state.goBack()
        state.goBack()
        XCTAssertEqual(state.index, 0)

        state.goBack()
        XCTAssertEqual(state.index, 0, "goBack at index 0 must not underflow")
    }

    func testGoBack_FromCompletionReturnsToLastBlock() {
        let state = LessonRunnerState(lesson: lesson(blockCount: 3))
        state.jump(to: 3)
        XCTAssertTrue(state.isComplete)

        state.goBack()
        XCTAssertEqual(state.index, 2)
        XCTAssertFalse(state.isComplete)
    }

    func testJump_IgnoresOutOfRangeTargets() {
        let state = LessonRunnerState(lesson: lesson(blockCount: 3))

        state.jump(to: -1)
        XCTAssertEqual(state.index, 0)

        state.jump(to: 99)
        XCTAssertEqual(state.index, 0)

        state.jump(to: 2)
        XCTAssertEqual(state.index, 2)
    }

    func testJump_AcceptsCompletionIndex() {
        let state = LessonRunnerState(lesson: lesson(blockCount: 3))
        state.jump(to: 3)
        XCTAssertTrue(state.isComplete)
    }

    func testReset_ReturnsToFirstBlock() {
        let state = LessonRunnerState(lesson: lesson(blockCount: 3))
        state.advance()
        state.advance()
        state.reset()
        XCTAssertEqual(state.index, 0)
        XCTAssertFalse(state.isComplete)
    }
}
