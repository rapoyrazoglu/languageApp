import SwiftUI

/// Family 4 — Listening. Three variants share the same base data shape
/// (`ListeningData`) and differ only in which fields they consume:
///
/// - `listening`: text `options` + `correctIndex` (audio-prompted MC)
/// - `dictation`: `answer` (full sentence the learner types)
/// - `listenAndAct`: `imageOptions` + `correctIndex` (tap correct image)
///
/// All three open with a prominent replay button — relistening is part of
/// the exercise, not a side-effect.
public struct ListeningExerciseView: View {
    public let data: ListeningData
    public let exerciseType: ExerciseType
    public let pack: InstalledPack
    public let onAudioRequest: (URL) -> Void
    public let onFinish: (Bool) -> Void

    @State private var selected: Int? = nil
    @State private var typed: String = ""
    @State private var submitted: Bool = false
    @State private var transcriptRevealed: Bool = false

    public init(
        data: ListeningData,
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                replayButton

                switch exerciseType {
                case .dictation:
                    dictationInput
                case .listenAndAct:
                    imageGrid
                default:
                    textChoices
                }

                if submitted {
                    feedback
                    if let transcript = data.transcript, !transcript.isEmpty {
                        transcriptDisclosure(text: transcript)
                    }
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
                    .disabled(!canSubmit)
                }
            }
            .padding()
        }
    }

    // MARK: - Sub-views

    private var replayButton: some View {
        HStack {
            Button {
                if let url = pack.mediaURL(forRelativePath: data.audio) {
                    onAudioRequest(url)
                }
            } label: {
                Label {
                    Text("button.playAudio", bundle: .module)
                } icon: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private var textChoices: some View {
        VStack(spacing: 12) {
            ForEach(Array((data.options ?? []).enumerated()), id: \.offset) { idx, option in
                choiceRow(idx: idx) {
                    Text(option).font(.body)
                }
            }
        }
    }

    private var imageGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array((data.imageOptions ?? []).enumerated()), id: \.offset) { idx, path in
                choiceRow(idx: idx) {
                    if let url = pack.mediaURL(forRelativePath: path) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFit()
                            default:
                                Color.secondary.opacity(0.1)
                            }
                        }
                        .frame(height: 140)
                    } else {
                        Color.secondary.opacity(0.1).frame(height: 140)
                    }
                }
            }
        }
    }

    private var dictationInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                "exercise.typing.placeholder",
                text: $typed,
                prompt: Text("exercise.typing.placeholder", bundle: .module),
                axis: .vertical
            )
            .lineLimit(2...5)
            .textFieldStyle(.roundedBorder)
            .disabled(submitted)
            #if os(iOS)
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)
            #endif
        }
    }

    private var feedback: some View {
        ExerciseFeedbackBanner(
            isCorrect: isCorrect,
            correctAnswer: isCorrect ? nil : correctAnswerLabel,
            explanation: nil
        )
    }

    private func transcriptDisclosure(text: String) -> some View {
        DisclosureGroup(isExpanded: $transcriptRevealed) {
            Text(text)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            Label {
                Text("exercise.label.explanation", bundle: .module)
            } icon: {
                Image(systemName: "text.alignleft")
            }
            .font(.callout)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func choiceRow<Content: View>(idx: Int, @ViewBuilder content: () -> Content) -> some View {
        Button {
            if !submitted { selected = idx }
        } label: {
            HStack {
                content()
                Spacer()
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
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(idx: idx))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(submitted)
    }

    private func rowBackground(idx: Int) -> Color {
        if submitted {
            if idx == data.correctIndex { return Color.green.opacity(0.12) }
            if idx == selected { return Color.red.opacity(0.12) }
            return Color.secondary.opacity(0.05)
        }
        return idx == selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06)
    }

    // MARK: - Logic

    private var canSubmit: Bool {
        switch exerciseType {
        case .dictation:
            return !typed.trimmingCharacters(in: .whitespaces).isEmpty
        default:
            return selected != nil
        }
    }

    private var isCorrect: Bool {
        switch exerciseType {
        case .dictation:
            guard let answer = data.answer else { return false }
            return TypingExerciseView.isAcceptable(
                input: typed,
                data: TypingData(
                    prompt: ExerciseMedia(),
                    answer: answer,
                    acceptedAlternatives: [],
                    caseSensitive: false
                )
            )
        default:
            return selected != nil && selected == data.correctIndex
        }
    }

    private var correctAnswerLabel: String? {
        switch exerciseType {
        case .dictation:
            return data.answer
        case .listenAndAct:
            return nil
        default:
            guard let idx = data.correctIndex,
                  let opts = data.options,
                  idx >= 0 && idx < opts.count
            else { return nil }
            return opts[idx]
        }
    }
}
