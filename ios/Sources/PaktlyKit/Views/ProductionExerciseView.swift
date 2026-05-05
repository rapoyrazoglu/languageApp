import SwiftUI

/// Family 9 — Production. Free-form text the learner writes; covers
/// `translateSentence` and `composeSentence`. Exact grading is a Phase 8
/// LLM concern — for now we score against three heuristics any creator can
/// rely on: minimum length, required words present, and a self-grade
/// against the reference answer the SDK reveals after submit. The "I got it
/// right" / "Need to retry" buttons let the learner record their own
/// outcome so spaced-repetition (Phase 6) can read it later.
public struct ProductionExerciseView: View {
    public let data: ProductionData
    public let pack: InstalledPack
    public let onAudioRequest: (URL) -> Void
    public let onFinish: (Bool) -> Void

    @State private var draft: String = ""
    @State private var submitted: Bool = false

    public init(
        data: ProductionData,
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

                editor

                metadata

                if submitted {
                    revealedReference
                    selfGradeButtons
                } else {
                    Button {
                        submitted = true
                    } label: {
                        Text("exercise.button.submit", bundle: .module)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!meetsMinimumRequirements)
                }
            }
            .padding()
        }
    }

    // MARK: - Sub-views

    private var editor: some View {
        TextEditor(text: $draft)
            .font(.body)
            .frame(minHeight: 120)
            .padding(8)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(submitted)
            #if os(iOS)
            .autocorrectionDisabled(false)
            #endif
    }

    private var metadata: some View {
        HStack(spacing: 12) {
            characterCount
            if !data.requiredWords.isEmpty { requiredWordsStatus }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var characterCount: some View {
        let count = draft.count
        var line = "\(count)"
        if let min = data.minLength { line += " / min \(min)" }
        if let max = data.maxLength { line += " / max \(max)" }
        return Text(line)
            .foregroundStyle(meetsLengthRequirements ? Color.secondary : Color.red)
    }

    private var requiredWordsStatus: some View {
        let missing = missingRequiredWords
        return HStack(spacing: 4) {
            Image(systemName: missing.isEmpty ? "checkmark.circle" : "circle.dashed")
                .foregroundStyle(missing.isEmpty ? Color.green : Color.secondary)
            Text("\(data.requiredWords.count - missing.count)/\(data.requiredWords.count) keywords")
        }
    }

    private var revealedReference: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reference = data.referenceAnswer, !reference.isEmpty {
                Text("exercise.label.correctAnswer", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(reference)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if !missingRequiredWords.isEmpty {
                Text("Missing: \(missingRequiredWords.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var selfGradeButtons: some View {
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
    }

    // MARK: - Logic

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var meetsLengthRequirements: Bool {
        let count = trimmed.count
        if let min = data.minLength, count < min { return false }
        if let max = data.maxLength, count > max { return false }
        return true
    }

    private var missingRequiredWords: [String] {
        let lower = trimmed.lowercased()
        return data.requiredWords.filter { !lower.contains($0.lowercased()) }
    }

    private var meetsMinimumRequirements: Bool {
        !trimmed.isEmpty && meetsLengthRequirements
    }
}
