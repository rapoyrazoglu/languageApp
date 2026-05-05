import SwiftUI

/// Dispatch entry-point for any exercise. Decodes the typed `ExerciseData`
/// once and routes to the right family view; falls back to the placeholder
/// view if the family isn't yet implemented or the payload is missing /
/// malformed. The lesson runner replaces its bottom navigation with this
/// view's own continue button while an exercise is on screen.
public struct ExerciseBlockView: View {
    public let block: ExerciseBlock
    public let pack: InstalledPack
    public let onAudioRequest: (URL) -> Void
    public let onFinish: (Bool) -> Void

    public init(
        block: ExerciseBlock,
        pack: InstalledPack,
        onAudioRequest: @escaping (URL) -> Void = { _ in },
        onFinish: @escaping (Bool) -> Void = { _ in }
    ) {
        self.block = block
        self.pack = pack
        self.onAudioRequest = onAudioRequest
        self.onFinish = onFinish
    }

    public var body: some View {
        if let payload = try? block.parseData() {
            view(for: payload)
        } else {
            ExercisePlaceholderView(block: block)
        }
    }

    @ViewBuilder
    private func view(for payload: ExerciseData) -> some View {
        switch payload {
        case .recall(let data):
            RecallExerciseView(
                data: data,
                exerciseType: block.exerciseType,
                pack: pack,
                onAudioRequest: onAudioRequest,
                onFinish: onFinish
            )
        case .multipleChoice(let data):
            MultipleChoiceExerciseView(
                data: data,
                pack: pack,
                onAudioRequest: onAudioRequest,
                onFinish: onFinish
            )
        case .typing(let data):
            TypingExerciseView(
                data: data,
                pack: pack,
                onAudioRequest: onAudioRequest,
                onFinish: onFinish
            )
        case .listening(let data):
            ListeningExerciseView(
                data: data,
                exerciseType: block.exerciseType,
                pack: pack,
                onAudioRequest: onAudioRequest,
                onFinish: onFinish
            )
        case .matching(let data):
            MatchingExerciseView(
                data: data,
                pack: pack,
                onAudioRequest: onAudioRequest,
                onFinish: onFinish
            )
        case .fillInBlank(let data):
            FillInBlankExerciseView(
                data: data,
                exerciseType: block.exerciseType,
                pack: pack,
                onAudioRequest: onAudioRequest,
                onFinish: onFinish
            )
        case .wordOrder(let data):
            WordOrderExerciseView(
                data: data,
                exerciseType: block.exerciseType,
                pack: pack,
                onAudioRequest: onAudioRequest,
                onFinish: onFinish
            )
        case .reading(let data):
            ReadingExerciseView(
                data: data,
                pack: pack,
                onAudioRequest: onAudioRequest,
                onFinish: onFinish
            )
        case .production(let data):
            ProductionExerciseView(
                data: data,
                pack: pack,
                onAudioRequest: onAudioRequest,
                onFinish: onFinish
            )
        case .categorization(let data):
            CategorizationExerciseView(
                data: data,
                exerciseType: block.exerciseType,
                pack: pack,
                onAudioRequest: onAudioRequest,
                onFinish: onFinish
            )
        case .raw:
            ExercisePlaceholderView(block: block)
        }
    }
}
