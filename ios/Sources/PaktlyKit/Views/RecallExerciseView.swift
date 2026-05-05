import SwiftUI

/// Family 1 — Recall. Covers `flashcard`, `flashcardReverse`, `flashcardAudio`,
/// `flashcardImage`. The data shape (front + back faces) is identical across
/// all four; the variant only changes which face starts visible. Audio /
/// image variants are conventions about which face fields creators populate.
public struct RecallExerciseView: View {
    public let data: FlashcardData
    public let exerciseType: ExerciseType
    public let pack: InstalledPack
    public let onAudioRequest: (URL) -> Void
    public let onFinish: (Bool) -> Void

    @State private var revealed: Bool = false

    public init(
        data: FlashcardData,
        exerciseType: ExerciseType,
        pack: InstalledPack,
        onAudioRequest: @escaping (URL) -> Void,
        onFinish: @escaping (Bool) -> Void
    ) {
        self.data = data
        self.exerciseType = exerciseType
        self.pack = pack
        self.onAudioRequest = onAudioRequest
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: 24) {
            cardSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .contentShape(RoundedRectangle(cornerRadius: 16))
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { revealed.toggle() }
                }

            if let hint = data.hint, !hint.isEmpty, !revealed {
                Label {
                    Text(hint)
                } icon: {
                    Image(systemName: "lightbulb")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if revealed {
                HStack(spacing: 12) {
                    Button {
                        onFinish(false)
                    } label: {
                        Text("exercise.recall.studyMore", bundle: .module)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onFinish(true)
                    } label: {
                        Text("exercise.recall.iKnew", bundle: .module)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text("exercise.recall.tapToReveal", bundle: .module)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .onChange(of: exerciseType) { _ in revealed = false }
    }

    private var cardSurface: some View {
        ExerciseMediaPrompt(
            media: visibleFace,
            pack: pack,
            onAudioRequest: onAudioRequest
        )
        .padding()
    }

    /// `flashcardReverse` flips the starting side: pre-reveal we show `back`,
    /// post-reveal we show `front`. The other three variants start on
    /// `front`. The data shape is identical.
    private var visibleFace: ExerciseMedia {
        let backFirst = exerciseType == .flashcardReverse
        if backFirst {
            return revealed ? data.front : data.back
        }
        return revealed ? data.back : data.front
    }
}
