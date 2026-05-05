import Foundation
import Combine

/// State container for a single in-progress lesson. Tracks an index into the
/// lesson's blocks and exposes navigation operations the UI binds to.
///
/// Index semantics: `[0, blocks.count)` points at a block; exactly
/// `blocks.count` represents "lesson finished" (used by the runner view to
/// switch to the completion screen). Empty lessons start in the finished
/// state.
///
/// All mutation runs on the main actor because the published index drives
/// SwiftUI redraws; SwiftUI requires that.
@MainActor
public final class LessonRunnerState: ObservableObject {
    public let lesson: Lesson
    @Published public private(set) var index: Int

    public init(lesson: Lesson) {
        self.lesson = lesson
        self.index = lesson.blocks.isEmpty ? 0 : 0
    }

    // MARK: - Derived state

    public var totalBlocks: Int { lesson.blocks.count }

    public var currentBlock: Block? {
        guard index >= 0 && index < lesson.blocks.count else { return nil }
        return lesson.blocks[index]
    }

    public var isEmpty: Bool { lesson.blocks.isEmpty }

    /// True once the user has stepped past the last block. Empty lessons are
    /// born complete (no content to consume).
    public var isComplete: Bool { isEmpty || index >= lesson.blocks.count }

    public var canAdvance: Bool { index < lesson.blocks.count }

    public var canGoBack: Bool { index > 0 }

    /// 0.0 at the first block, 1.0 once the lesson is complete. Drives the
    /// progress bar; clamped because callers occasionally over-advance.
    public var progress: Double {
        guard totalBlocks > 0 else { return 1.0 }
        let clamped = max(0, min(index, totalBlocks))
        return Double(clamped) / Double(totalBlocks)
    }

    // MARK: - Mutations

    public func advance() {
        guard canAdvance else { return }
        index += 1
    }

    public func goBack() {
        guard canGoBack else { return }
        index -= 1
    }

    /// Jump to an arbitrary block index. Out-of-range targets are silently
    /// ignored — UI surfaces shouldn't be able to wedge state by jamming a
    /// stale value.
    public func jump(to target: Int) {
        guard target >= 0 && target <= lesson.blocks.count else { return }
        index = target
    }

    public func reset() {
        index = 0
    }
}
