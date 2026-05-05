import SwiftUI

/// Family 3 — Typing. Covers `typing`, `typingReverse`, `typingAudio`. The
/// view doesn't care which variant — the prompt's media fields tell it what
/// to render. Answer matching is whitespace-trimmed, optionally
/// case-sensitive, and consults `acceptedAlternatives` so creators can offer
/// e.g. romaji + kana for the same answer.
public struct TypingExerciseView: View {
    public let data: TypingData
    public let pack: InstalledPack
    public let onAudioRequest: (URL) -> Void
    public let onFinish: (Bool) -> Void

    @State private var input: String = ""
    @State private var submitted: Bool = false

    public init(
        data: TypingData,
        pack: InstalledPack,
        onAudioRequest: @escaping (URL) -> Void,
        onFinish: @escaping (Bool) -> Void
    ) {
        self.data = data
        self.pack = pack
        self.onAudioRequest = onAudioRequest
        self.onFinish = onFinish
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ExerciseMediaPrompt(media: data.prompt, pack: pack, onAudioRequest: onAudioRequest)

                TextField(
                    "exercise.typing.placeholder",
                    text: $input,
                    prompt: Text("exercise.typing.placeholder", bundle: .module)
                )
                .textFieldStyle(.roundedBorder)
                .disabled(submitted)
                .submitLabel(.done)
                .onSubmit { submit() }
                #if os(iOS)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                #endif

                if let hint = data.hint, !hint.isEmpty, !submitted {
                    Label {
                        Text(hint)
                    } icon: {
                        Image(systemName: "lightbulb")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if submitted {
                    let isCorrect = TypingExerciseView.isAcceptable(input: input, data: data)
                    ExerciseFeedbackBanner(
                        isCorrect: isCorrect,
                        correctAnswer: isCorrect ? nil : data.answer,
                        explanation: nil
                    )
                    Button {
                        onFinish(isCorrect)
                    } label: {
                        Text("exercise.button.continue", bundle: .module)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        submit()
                    } label: {
                        Text("exercise.button.submit", bundle: .module)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding()
        }
    }

    private func submit() {
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        submitted = true
    }

    /// Public so the answer-checking logic is testable in isolation; the
    /// view layer is otherwise SwiftUI runtime territory.
    public static func isAcceptable(input: String, data: TypingData) -> Bool {
        let normalize: (String) -> String = { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return data.caseSensitive ? trimmed : trimmed.lowercased()
        }
        let normalised = normalize(input)
        if normalised == normalize(data.answer) { return true }
        return data.acceptedAlternatives.contains { normalize($0) == normalised }
    }
}
