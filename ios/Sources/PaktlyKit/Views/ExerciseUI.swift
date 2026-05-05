import SwiftUI

/// Shared UI primitives used by every exercise family view. Centralised here
/// so a tweak (e.g. switching the feedback banner palette) lands everywhere
/// at once instead of needing to ripple through each family.

// MARK: - Media prompt

/// Renders an `ExerciseMedia` block. Exercises put the prompt at the top —
/// some have only text, some only audio, some only an image, some a mix.
/// We render whichever fields are populated and skip the rest cleanly.
struct ExerciseMediaPrompt: View {
    let media: ExerciseMedia
    let pack: InstalledPack
    let onAudioRequest: (URL) -> Void

    var body: some View {
        VStack(spacing: 12) {
            if let text = media.text, !text.isEmpty {
                Text(text)
                    .font(.title3)
                    .multilineTextAlignment(.center)
            }
            if let audioPath = media.audio, let url = pack.mediaURL(forRelativePath: audioPath) {
                Button {
                    onAudioRequest(url)
                } label: {
                    Label {
                        Text("button.playAudio", bundle: .module)
                    } icon: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                }
                .buttonStyle(.bordered)
            }
            if let imagePath = media.image, let url = pack.mediaURL(forRelativePath: imagePath) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        Color.clear.frame(height: 0)
                    }
                }
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Feedback banner

struct ExerciseFeedbackBanner: View {
    let isCorrect: Bool
    let correctAnswer: String?
    let explanation: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                Text(
                    LocalizedStringKey(
                        isCorrect ? "exercise.feedback.correct" : "exercise.feedback.incorrect"
                    ),
                    bundle: .module
                )
                .bold()
            }
            .font(.headline)
            .foregroundStyle(isCorrect ? Color.green : Color.red)

            if let correctAnswer, !isCorrect {
                Text("exercise.label.correctAnswer", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(correctAnswer)
                    .font(.body)
            }
            if let explanation, !explanation.isEmpty {
                Text("exercise.label.explanation", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(explanation)
                    .font(.callout)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isCorrect ? Color.green : Color.red).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Placeholder for unimplemented families

/// Surface enough metadata so a creator can verify their pack parses even if
/// the renderer for a given exercise family hasn't shipped yet.
struct ExercisePlaceholderView: View {
    let block: ExerciseBlock

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.app.dashed")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("exercise.placeholder.title", bundle: .module)
                .font(.title3)
                .bold()

            if let prompt = block.prompt, !prompt.isEmpty {
                Text(prompt)
                    .font(.body)
                    .multilineTextAlignment(.center)
            }

            Text(block.exerciseType.rawValue)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())

            Text("exercise.placeholder.body", bundle: .module)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
