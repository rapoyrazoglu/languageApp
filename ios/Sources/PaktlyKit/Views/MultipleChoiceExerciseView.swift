import SwiftUI

/// Family 2 — MultipleChoice. Covers all 5 variants: text, reverse, audio,
/// image, context. They share the same data shape (prompt + 4ish options +
/// correctIndex); the variant only affects which media slot the prompt fills.
public struct MultipleChoiceExerciseView: View {
    public let data: MultipleChoiceData
    public let pack: InstalledPack
    public let onAudioRequest: (URL) -> Void
    public let onFinish: (Bool) -> Void

    @State private var selected: Int? = nil
    @State private var submitted: Bool = false

    public init(
        data: MultipleChoiceData,
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
                    .padding(.bottom, 4)

                ForEach(Array(data.options.enumerated()), id: \.offset) { idx, option in
                    optionRow(idx: idx, label: option)
                }

                if submitted {
                    let isCorrect = selected == data.correctIndex
                    ExerciseFeedbackBanner(
                        isCorrect: isCorrect,
                        correctAnswer: isCorrect ? nil : safeOption(at: data.correctIndex),
                        explanation: data.explanation
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
                        submitted = true
                    } label: {
                        Text("exercise.button.submit", bundle: .module)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected == nil)
                }
            }
            .padding()
        }
    }

    private func optionRow(idx: Int, label: String) -> some View {
        Button {
            if !submitted { selected = idx }
        } label: {
            HStack {
                Text(label)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                Spacer()
                trailingIcon(for: idx)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background(for: idx))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor(for: idx), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(submitted)
    }

    @ViewBuilder
    private func trailingIcon(for idx: Int) -> some View {
        if submitted {
            if idx == data.correctIndex {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if idx == selected {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            }
        } else if idx == selected {
            Image(systemName: "circle.inset.filled").foregroundStyle(.tint)
        }
    }

    private func background(for idx: Int) -> Color {
        if submitted {
            if idx == data.correctIndex { return Color.green.opacity(0.12) }
            if idx == selected { return Color.red.opacity(0.12) }
            return Color.secondary.opacity(0.05)
        }
        return idx == selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06)
    }

    private func borderColor(for idx: Int) -> Color {
        if submitted {
            if idx == data.correctIndex { return .green.opacity(0.6) }
            if idx == selected { return .red.opacity(0.6) }
            return .clear
        }
        return idx == selected ? .accentColor : .clear
    }

    private func safeOption(at index: Int) -> String? {
        guard index >= 0 && index < data.options.count else { return nil }
        return data.options[index]
    }
}
