import SwiftUI

/// Renders an entire lesson, switching block-by-block as the user advances.
/// Phase 3d covers explanation + vocabulary; exercises display a "coming
/// soon" placeholder until Phase 3e lands the interactive views.
///
/// Audio is delegated: the runner exposes the resolved on-disk file URL
/// through `onAudioRequest`. Phase 3f wires AVFoundation underneath; for
/// now any host can supply its own player closure.
public struct LessonRunnerView: View {
    @StateObject private var state: LessonRunnerState
    private let pack: InstalledPack
    private let onAudioRequest: (URL) -> Void
    private let onComplete: () -> Void

    public init(
        lesson: Lesson,
        in pack: InstalledPack,
        onAudioRequest: @escaping (URL) -> Void = { _ in },
        onComplete: @escaping () -> Void = {}
    ) {
        _state = StateObject(wrappedValue: LessonRunnerState(lesson: lesson))
        self.pack = pack
        self.onAudioRequest = onAudioRequest
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: state.progress)
                .progressViewStyle(.linear)
                .padding(.horizontal)
                .padding(.top, 8)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Exercises drive their own advance via the family view's
            // Continue button (so the user sees correct/incorrect feedback
            // before moving on); the lesson-level nav bar would compete
            // with it. Hide it while an exercise is on screen.
            if showsLessonNav {
                controls
            }
        }
    }

    private var showsLessonNav: Bool {
        guard let block = state.currentBlock else { return true }
        if case .exercise = block { return false }
        return true
    }

    // MARK: - Content router

    @ViewBuilder
    private var content: some View {
        if state.isEmpty {
            EmptyLessonView()
        } else if state.isComplete {
            CompletionView()
        } else if let block = state.currentBlock {
            view(for: block)
        }
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .explanation(let b):
            ExplanationBlockView(block: b, pack: pack, onAudioRequest: onAudioRequest)
        case .vocabulary(let b):
            VocabularyBlockView(block: b, pack: pack, onAudioRequest: onAudioRequest)
        case .exercise(let b):
            ExerciseBlockView(
                block: b,
                pack: pack,
                onAudioRequest: onAudioRequest,
                onFinish: { _ in handleAdvance() }
            )
        }
    }

    // MARK: - Bottom navigation

    private var controls: some View {
        HStack {
            Button(action: { state.goBack() }) {
                Label {
                    Text("button.previous", bundle: .module)
                } icon: {
                    Image(systemName: "chevron.left")
                }
            }
            .buttonStyle(.bordered)
            .disabled(!state.canGoBack)

            Spacer()

            Button(action: handleAdvance) {
                let isLast = state.index == max(0, state.totalBlocks - 1)
                Label {
                    Text(LocalizedStringKey(isLast ? "button.finish" : "button.next"), bundle: .module)
                } icon: {
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!state.canAdvance)
        }
        .padding()
    }

    private func handleAdvance() {
        let wasOnLast = state.index == state.totalBlocks - 1
        state.advance()
        if wasOnLast { onComplete() }
    }
}

// MARK: - Helper screens

struct EmptyLessonView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("lesson.empty.title", bundle: .module)
                .font(.headline)
            Text("lesson.empty.body", bundle: .module)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct CompletionView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("lesson.complete.title", bundle: .module)
                .font(.title2)
                .bold()
            Text("lesson.complete.body", bundle: .module)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
