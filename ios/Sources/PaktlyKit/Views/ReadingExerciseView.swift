import SwiftUI

/// Family 8 — Reading. A passage at the top followed by 1-N questions, each
/// of which is true/false, multiple-choice, or cloze. We render the passage
/// once and walk the questions inline below it; the user answers each before
/// hitting submit, and the view then scores the whole exercise as a single
/// pass / fail (correct iff every answer was right).
public struct ReadingExerciseView: View {
    public let data: ReadingData
    public let pack: InstalledPack
    public let onAudioRequest: (URL) -> Void
    public let onFinish: (Bool) -> Void

    @State private var mcSelections: [Int: Int] = [:]
    @State private var tfSelections: [Int: Bool] = [:]
    @State private var clozeAnswers: [Int: [String]] = [:]
    @State private var submitted: Bool = false

    public init(
        data: ReadingData,
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
                passage
                if !data.glossary.isEmpty { glossary }

                Divider()

                ForEach(Array(data.questions.enumerated()), id: \.offset) { idx, question in
                    questionView(idx: idx, question: question)
                    if idx < data.questions.count - 1 { Divider() }
                }

                if submitted {
                    ExerciseFeedbackBanner(
                        isCorrect: isAllCorrect,
                        correctAnswer: nil,
                        explanation: scoreLine
                    )
                    Button {
                        onFinish(isAllCorrect)
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
                    .disabled(!allAnswered)
                }
            }
            .padding()
        }
    }

    // MARK: - Sub-views

    private var passage: some View {
        Text(data.passage)
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var glossary: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(data.glossary.sorted(by: { $0.key < $1.key }), id: \.key) { word, gloss in
                    HStack {
                        Text(word).bold()
                        Text("—").foregroundStyle(.secondary)
                        Text(gloss).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
            .padding(.top, 4)
        } label: {
            Label {
                Text("Glossary")  // Generic label — could localise later if a glossary key is added.
            } icon: {
                Image(systemName: "book.pages")
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private func questionView(idx: Int, question: ReadingQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.prompt).font(.body)

            switch question.kind {
            case .trueFalse:
                trueFalseControls(idx: idx, question: question)
            case .multipleChoice:
                mcControls(idx: idx, question: question)
            case .cloze:
                clozeControls(idx: idx, question: question)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func trueFalseControls(idx: Int, question: ReadingQuestion) -> some View {
        HStack(spacing: 8) {
            ForEach([true, false], id: \.self) { value in
                Button {
                    if !submitted { tfSelections[idx] = value }
                } label: {
                    HStack {
                        Image(systemName: value ? "checkmark.circle" : "xmark.circle")
                        Text(value ? "True" : "False")
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(tfBackground(idx: idx, value: value, question: question))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(submitted)
            }
        }
    }

    private func tfBackground(idx: Int, value: Bool, question: ReadingQuestion) -> Color {
        if !submitted {
            return tfSelections[idx] == value ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08)
        }
        if value == question.truthy { return Color.green.opacity(0.18) }
        if tfSelections[idx] == value { return Color.red.opacity(0.18) }
        return Color.secondary.opacity(0.05)
    }

    private func mcControls(idx: Int, question: ReadingQuestion) -> some View {
        VStack(spacing: 6) {
            ForEach(Array((question.options ?? []).enumerated()), id: \.offset) { optIdx, opt in
                Button {
                    if !submitted { mcSelections[idx] = optIdx }
                } label: {
                    HStack {
                        Text(opt)
                        Spacer()
                        if submitted {
                            if optIdx == question.correctIndex {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else if mcSelections[idx] == optIdx {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                            }
                        } else if mcSelections[idx] == optIdx {
                            Image(systemName: "circle.inset.filled").foregroundStyle(.tint)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(mcBackground(idx: idx, optIdx: optIdx, question: question))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(submitted)
            }
        }
    }

    private func mcBackground(idx: Int, optIdx: Int, question: ReadingQuestion) -> Color {
        if !submitted {
            return mcSelections[idx] == optIdx ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.06)
        }
        if optIdx == question.correctIndex { return Color.green.opacity(0.14) }
        if mcSelections[idx] == optIdx { return Color.red.opacity(0.14) }
        return Color.secondary.opacity(0.05)
    }

    private func clozeControls(idx: Int, question: ReadingQuestion) -> some View {
        // Cloze rendering reuses the FillInBlank approach for the rare case
        // a reading exercise embeds a free-text fill-in. Phase 3e.5 keeps
        // it simple: one TextField per declared answer slot.
        let count = question.answers?.count ?? 1
        return VStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { slot in
                TextField(
                    "exercise.typing.placeholder",
                    text: Binding(
                        get: { (clozeAnswers[idx]?[safe: slot]) ?? "" },
                        set: { newValue in
                            var arr = clozeAnswers[idx] ?? Array(repeating: "", count: count)
                            while arr.count <= slot { arr.append("") }
                            arr[slot] = newValue
                            clozeAnswers[idx] = arr
                        }
                    ),
                    prompt: Text("exercise.typing.placeholder", bundle: .module)
                )
                .textFieldStyle(.roundedBorder)
                .disabled(submitted)
                #if os(iOS)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                #endif
            }
        }
    }

    // MARK: - Logic

    private var allAnswered: Bool {
        for (idx, q) in data.questions.enumerated() {
            switch q.kind {
            case .trueFalse:
                if tfSelections[idx] == nil { return false }
            case .multipleChoice:
                if mcSelections[idx] == nil { return false }
            case .cloze:
                guard let ans = clozeAnswers[idx], ans.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return false }
                if ans.count < (q.answers?.count ?? 1) { return false }
            }
        }
        return true
    }

    private var correctCount: Int {
        var n = 0
        for (idx, q) in data.questions.enumerated() {
            if isQuestionCorrect(idx: idx, q: q) { n += 1 }
        }
        return n
    }

    private var isAllCorrect: Bool { correctCount == data.questions.count }

    private var scoreLine: String? {
        "\(correctCount) / \(data.questions.count)"
    }

    private func isQuestionCorrect(idx: Int, q: ReadingQuestion) -> Bool {
        switch q.kind {
        case .trueFalse:
            return tfSelections[idx] == q.truthy
        case .multipleChoice:
            return mcSelections[idx] == q.correctIndex
        case .cloze:
            guard let userAns = clozeAnswers[idx], let truth = q.answers, userAns.count == truth.count else { return false }
            for (a, expected) in zip(userAns, truth) {
                if a.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    != expected.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                    return false
                }
            }
            return true
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
