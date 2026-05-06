import SwiftUI
import PaktlyKit

/// Renders one lesson by switching on the current block. Owns the
/// `LessonRunnerState` directly (instead of letting `LessonRunnerView` bury
/// it) so RootView can present back/next chevrons next to the floating tab
/// bar — same layer, same physics. Audio is delegated through
/// `services.audioPlayer`.
///
/// The user navigates the lesson three ways:
///   1. The flanking ← / → on the floating tab bar (non-exercise blocks).
///   2. The exercise block's own continue button (exercises self-advance
///      after submit so the user sees correct/incorrect feedback first).
///   3. The system back chevron in the navigation bar to leave the lesson.
struct LessonRunnerScreen: View {
    @EnvironmentObject private var services: AppServices

    let pack: InstalledPack
    let lessonRef: LessonRef

    @StateObject private var state: LessonRunnerState
    @State private var loadError: String?
    private let lessonResolved: Bool

    init(pack: InstalledPack, lessonRef: LessonRef) {
        self.pack = pack
        self.lessonRef = lessonRef

        // Lesson JSON lives on the local filesystem — load synchronously so
        // we can hand a fully-built state to the @StateObject. Failure
        // produces an empty placeholder lesson and surfaces an error
        // message; the screen handles the empty case cleanly.
        let lesson: Lesson
        let resolved: Bool
        if let loaded = try? pack.lesson(id: lessonRef.id) {
            lesson = loaded
            resolved = true
        } else {
            lesson = Lesson(id: lessonRef.id, title: lessonRef.title ?? lessonRef.id, blocks: [])
            resolved = false
        }
        self._state = StateObject(wrappedValue: LessonRunnerState(lesson: lesson))
        self.lessonResolved = resolved
    }

    var body: some View {
        ZStack {
            DS.background.ignoresSafeArea()

            if !lessonResolved {
                loadFailureView
            } else if state.isEmpty {
                emptyLessonView
            } else if state.isComplete {
                completionView
            } else if let block = state.currentBlock {
                contentView(for: block)
            }
        }
        .navigationTitle(state.lesson.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DS.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            services.activeLessonState = state
            services.setCurrentLesson(packId: pack.packId, lessonId: lessonRef.id)
        }
        .onDisappear {
            services.activeLessonState = nil
            services.audioPlayer.stop()
        }
    }

    // MARK: - Block routing

    @ViewBuilder
    private func contentView(for block: Block) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                switch block {
                case .explanation(let b):
                    ExplanationBlockView(
                        block: b,
                        pack: pack,
                        onAudioRequest: { services.audioPlayer.play($0) }
                    )
                case .vocabulary(let b):
                    VocabularyBlockView(
                        block: b,
                        pack: pack,
                        onAudioRequest: { services.audioPlayer.play($0) }
                    )
                case .exercise(let b):
                    ExerciseBlockView(
                        block: b,
                        pack: pack,
                        onAudioRequest: { services.audioPlayer.play($0) },
                        onFinish: { _ in state.advance() }
                    )
                // Schema 1.2.0+ blocks. Demo's lesson runner doesn't have
                // dedicated views for these yet — they're scheduled for the
                // content design pass. Show a compact placeholder so 1.2.0
                // packs don't crash and the user can still advance.
                case .dialogue(let b):
                    UnrenderedBlockNotice(label: "dialogue", detail: "\(b.lines.count) line\(b.lines.count == 1 ? "" : "s")")
                case .kanji(let b):
                    UnrenderedBlockNotice(label: "kanji", detail: "\(b.items.count) item\(b.items.count == 1 ? "" : "s")")
                case .grammar(let b):
                    UnrenderedBlockNotice(label: "grammar", detail: b.pattern)
                }
            }
            // Pad the bottom so block content never sits behind the floating
            // tab bar + chevron row at the bottom of the screen.
            .padding(.bottom, 120)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Edge states

    private var emptyLessonView: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.largeTitle)
                .foregroundStyle(DS.textTertiary)
            Text("lesson.empty.title").font(.dsHeadline)
            Text("lesson.empty.body")
                .font(.dsCallout)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var completionView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(DS.accent.opacity(0.18))
                    .frame(width: 140, height: 140)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 76, weight: .heavy))
                    .foregroundStyle(DS.accent)
            }
            Text("lesson.complete.title")
                .font(.dsTitle)
                .foregroundStyle(DS.textPrimary)
            Text("lesson.complete.body")
                .font(.dsCallout)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadFailureView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(DS.warning)
            Text("error.lessonLoadFailed").font(.dsHeadline)
        }
        .padding()
    }
}


/// Visible-but-minimal stand-in for schema 1.2.0 blocks the demo's lesson
/// runner doesn't render yet (`dialogue`, `kanji`, `grammar`). Keeps the
/// runner schema-compatible with 1.2.0 packs while a follow-up content
/// design pass produces dedicated views.
private struct UnrenderedBlockNotice: View {
    let label: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.title)
                .foregroundStyle(DS.textTertiary)
            Text(label.uppercased())
                .font(.dsCaption)
                .tracking(0.08)
                .foregroundStyle(DS.textSecondary)
            Text(detail)
                .font(.dsHeadline)
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }
}
