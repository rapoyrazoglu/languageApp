import SwiftUI
import PaktlyKit

/// Sheet that gates jumping ahead in the lesson path. The user can't tap
/// from lesson 1 directly to lesson 5 — they have to either work through
/// 2-4 normally, or pass a placement test sampling exercises from those
/// skipped lessons. Pass threshold is 80%; samples up to 5 questions.
///
/// Phase 6 SRS will deepen this with proper spaced-repetition difficulty
/// weighting and per-item history. For now this is the simple "test out"
/// flow that gives the user agency without flooding them with cheap
/// shortcuts.
struct PlacementTestSheet: View {
    let pack: InstalledPack
    let target: LessonRef
    let lessonsToCover: [LessonRef]
    let onPass: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var services: AppServices

    @State private var phase: Phase = .intro
    @State private var sampled: [SampledQuestion] = []
    @State private var current: Int = 0
    @State private var correctCount: Int = 0

    private let passThreshold: Double = 0.8
    private let maxQuestions: Int = 5

    enum Phase: Equatable {
        case intro
        case running
        case result(passed: Bool)
        case noQuestions
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.background.ignoresSafeArea()
                content
            }
            .navigationTitle("placement.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DS.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("auth.cancel") { dismiss() }
                        .foregroundStyle(DS.accent)
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .intro:
            introScreen
        case .running:
            runningScreen
        case .result(let passed):
            resultScreen(passed: passed)
        case .noQuestions:
            noQuestionsScreen
        }
    }

    // MARK: - Intro

    private var introScreen: some View {
        ScrollView {
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(DS.accentMuted)
                        .frame(width: 120, height: 120)
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 56, weight: .heavy))
                        .foregroundStyle(DS.accent)
                }
                .padding(.top, 8)

                VStack(spacing: 8) {
                    Text("placement.intro.title")
                        .font(.dsTitle)
                        .foregroundStyle(DS.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(
                        String(
                            format: NSLocalizedString("placement.intro.body", comment: ""),
                            target.title ?? target.id,
                            lessonsToCover.count
                        )
                    )
                    .font(.dsCallout)
                    .foregroundStyle(DS.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                }

                lessonsList

                Spacer(minLength: 24)

                Button {
                    start()
                } label: {
                    Text("placement.begin")
                }
                .buttonStyle(.primaryPill)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
            .padding(.top, 16)
        }
        .scrollContentBackground(.hidden)
    }

    private var lessonsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("placement.intro.coversList")
                .font(.dsCaption)
                .foregroundStyle(DS.textSecondary)
                .textCase(.uppercase)
                .tracking(0.6)

            VStack(spacing: 6) {
                ForEach(lessonsToCover, id: \.id) { ref in
                    HStack(spacing: 10) {
                        Image(systemName: "circle.dashed")
                            .foregroundStyle(DS.accent)
                            .font(.system(size: 14, weight: .heavy))
                        Text(ref.title ?? ref.id)
                            .font(.dsBody)
                            .foregroundStyle(DS.textPrimary)
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .padding(.horizontal, 16)
    }

    // MARK: - Running

    private var runningScreen: some View {
        VStack(spacing: 0) {
            progressHeader

            Divider().background(DS.divider)

            if let question = sampled[safe: current] {
                ExerciseBlockView(
                    block: question.block,
                    pack: pack,
                    onAudioRequest: { url in services.audioPlayer.play(url) },
                    onFinish: { correct in
                        if correct { correctCount += 1 }
                        advance()
                    }
                )
                .id(current)  // force remount per question
            } else {
                ProgressView().tint(DS.accent)
            }
        }
    }

    private var progressHeader: some View {
        VStack(spacing: 6) {
            HStack {
                Text(
                    String(
                        format: NSLocalizedString("placement.progress", comment: ""),
                        current + 1,
                        sampled.count
                    )
                )
                .font(.dsCaption)
                .foregroundStyle(DS.textSecondary)
                Spacer()
                Text(
                    String(
                        format: NSLocalizedString("placement.scoreSoFar", comment: ""),
                        correctCount
                    )
                )
                .font(.dsCaption)
                .foregroundStyle(DS.textSecondary)
            }
            ProgressView(value: Double(current), total: Double(max(1, sampled.count)))
                .progressViewStyle(.linear)
                .tint(DS.accent)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    // MARK: - Result

    private func resultScreen(passed: Bool) -> some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill((passed ? DS.accent : DS.danger).opacity(0.18))
                    .frame(width: 140, height: 140)
                Image(systemName: passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.system(size: 72, weight: .heavy))
                    .foregroundStyle(passed ? DS.accent : DS.danger)
            }

            VStack(spacing: 6) {
                Text(LocalizedStringKey(passed ? "placement.passed.title" : "placement.failed.title"))
                    .font(.dsTitle)
                    .foregroundStyle(DS.textPrimary)
                Text(
                    String(
                        format: NSLocalizedString(
                            passed ? "placement.passed.body" : "placement.failed.body",
                            comment: ""
                        ),
                        correctCount,
                        sampled.count
                    )
                )
                .font(.dsCallout)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 10) {
                if passed {
                    Button {
                        onPass()
                        dismiss()
                    } label: {
                        Text(LocalizedStringKey(
                            String(format: NSLocalizedString("placement.passed.cta", comment: ""), target.title ?? target.id)
                        ))
                    }
                    .buttonStyle(.primaryPill)
                } else {
                    Button {
                        dismiss()
                    } label: {
                        Text("placement.failed.workThrough")
                    }
                    .buttonStyle(.primaryPill)
                    Button {
                        retry()
                    } label: {
                        Text("placement.failed.retry")
                    }
                    .buttonStyle(.secondaryPill)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }

    // MARK: - No questions available

    private var noQuestionsScreen: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(DS.textTertiary)
            Text("placement.noQuestions.title")
                .font(.dsTitle2)
                .foregroundStyle(DS.textPrimary)
            Text("placement.noQuestions.body")
                .font(.dsCallout)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("placement.noQuestions.ok")
            }
            .buttonStyle(.primaryPill)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Logic

    private func start() {
        let pool = collectQuestions()
        if pool.isEmpty {
            phase = .noQuestions
            return
        }
        sampled = pool.shuffled().prefix(maxQuestions).map { $0 }
        current = 0
        correctCount = 0
        phase = .running
    }

    private func advance() {
        let next = current + 1
        if next >= sampled.count {
            let score = Double(correctCount) / Double(max(1, sampled.count))
            phase = .result(passed: score >= passThreshold)
        } else {
            current = next
        }
    }

    private func retry() {
        start()
    }

    /// Pull every exercise block from each lesson the user is trying to
    /// skip. We only sample types whose runners can stand alone in the
    /// sheet (text-driven multipleChoice + typing); audio / drag-based
    /// types still render but rely on bigger surface area than the sheet
    /// gives them, so they sit out for now. Phase 6 widens the pool.
    private func collectQuestions() -> [SampledQuestion] {
        var out: [SampledQuestion] = []
        for ref in lessonsToCover {
            guard let lesson = try? pack.lesson(id: ref.id) else { continue }
            for block in lesson.blocks {
                if case .exercise(let ex) = block {
                    if isSampleable(ex) {
                        out.append(SampledQuestion(lessonRef: ref, block: ex))
                    }
                }
            }
        }
        return out
    }

    private func isSampleable(_ ex: ExerciseBlock) -> Bool {
        switch ex.exerciseType.family {
        case .multipleChoice, .typing, .recall:
            return true
        default:
            return false
        }
    }
}

private struct SampledQuestion: Identifiable {
    let lessonRef: LessonRef
    let block: ExerciseBlock
    var id: String { "\(lessonRef.id)|\(block.exerciseType.rawValue)" }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
