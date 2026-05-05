import SwiftUI

/// Family 6 — FillInBlank. The pack ships a `template` peppered with
/// `{{1}}`, `{{2}}` markers and a parallel `answers` array. Three variants:
/// - `fillInBlank`: free typing per blank
/// - `fillInBlankChoice`: tap from a fixed `options` pool to fill the
///   currently-focused blank
/// - `fillInMultiple`: same as fillInBlank but with several blanks per
///   sentence
public struct FillInBlankExerciseView: View {
    public let data: FillInBlankData
    public let exerciseType: ExerciseType
    public let pack: InstalledPack
    public let onAudioRequest: (URL) -> Void
    public let onFinish: (Bool) -> Void

    @State private var typedAnswers: [String] = []
    @State private var optionAssignments: [Int?] = []
    @State private var focusedBlank: Int? = nil
    @State private var submitted: Bool = false

    public init(
        data: FillInBlankData,
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
                templateRendering

                if exerciseType == .fillInBlankChoice, let pool = data.options {
                    Divider()
                    optionPool(pool: pool)
                }

                if submitted {
                    ExerciseFeedbackBanner(
                        isCorrect: isCorrect,
                        correctAnswer: isCorrect ? nil : correctSentence,
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
                        submitted = true
                    } label: {
                        Text("exercise.button.submit", bundle: .module)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!allBlanksFilled)
                }
            }
            .padding()
        }
        .onAppear(perform: setupIfNeeded)
    }

    // MARK: - Template render

    private var templateRendering: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(parsedSegments.enumerated()), id: \.offset) { _, seg in
                switch seg {
                case .text(let text):
                    Text(text).font(.body)
                case .blank(let blankIdx):
                    blankView(idx: blankIdx)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func blankView(idx: Int) -> some View {
        if exerciseType == .fillInBlankChoice {
            chipBlank(idx: idx)
        } else {
            inlineTextField(idx: idx)
        }
    }

    private func chipBlank(idx: Int) -> some View {
        let label = optionAssignments[safe: idx]
            .flatMap { opt in opt.flatMap { data.options?[$0] } }
            ?? "_____"
        return Button {
            if !submitted { focusedBlank = idx }
        } label: {
            Text(label)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(blankBackground(idx: idx))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(focusedBlank == idx ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(submitted)
    }

    private func inlineTextField(idx: Int) -> some View {
        TextField("", text: Binding(
            get: { typedAnswers[safe: idx] ?? "" },
            set: { newValue in
                if typedAnswers.indices.contains(idx) { typedAnswers[idx] = newValue }
            }
        ))
        .textFieldStyle(.roundedBorder)
        .frame(minWidth: 80)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(submitted)
        #if os(iOS)
        .autocorrectionDisabled(true)
        .textInputAutocapitalization(.never)
        #endif
    }

    private func blankBackground(idx: Int) -> Color {
        if !submitted { return Color.secondary.opacity(0.12) }
        return isBlankCorrect(idx: idx) ? Color.green.opacity(0.18) : Color.red.opacity(0.18)
    }

    private func optionPool(pool: [String]) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(pool.enumerated()), id: \.offset) { idx, option in
                let inUse = optionAssignments.contains(idx)
                Button {
                    guard let blank = focusedBlank, !submitted else { return }
                    if inUse, let prev = optionAssignments.firstIndex(of: idx) {
                        optionAssignments[prev] = nil
                    }
                    optionAssignments[blank] = idx
                    focusedBlank = nil
                } label: {
                    Text(option)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(inUse ? Color.secondary.opacity(0.12) : Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .opacity(inUse ? 0.6 : 1.0)
                }
                .buttonStyle(.plain)
                .disabled(submitted || focusedBlank == nil)
            }
        }
    }

    // MARK: - Setup

    private func setupIfNeeded() {
        if typedAnswers.isEmpty {
            typedAnswers = Array(repeating: "", count: data.answers.count)
        }
        if optionAssignments.isEmpty {
            optionAssignments = Array(repeating: nil, count: data.answers.count)
        }
    }

    // MARK: - Logic

    private var allBlanksFilled: Bool {
        if exerciseType == .fillInBlankChoice {
            return !optionAssignments.contains(where: { $0 == nil })
        }
        return typedAnswers.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var isCorrect: Bool {
        guard data.answers.count == typedAnswers.count else { return false }
        for blankIdx in data.answers.indices {
            if !isBlankCorrect(idx: blankIdx) { return false }
        }
        return true
    }

    private func isBlankCorrect(idx: Int) -> Bool {
        guard data.answers.indices.contains(idx) else { return false }
        let expected = data.answers[idx]
        let alts = data.acceptedAlternatives.indices.contains(idx) ? data.acceptedAlternatives[idx] : []

        let normalize: (String) -> String = { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return data.caseSensitive ? trimmed : trimmed.lowercased()
        }

        let actualText: String
        if exerciseType == .fillInBlankChoice {
            guard let optIdx = optionAssignments[safe: idx]?.flatMap({ $0 }),
                  let opt = data.options?[safe: optIdx]
            else { return false }
            actualText = opt
        } else {
            actualText = typedAnswers[safe: idx] ?? ""
        }

        let actualNormalised = normalize(actualText)
        if actualNormalised == normalize(expected) { return true }
        return alts.contains { normalize($0) == actualNormalised }
    }

    private var correctSentence: String {
        var rendered = ""
        for seg in parsedSegments {
            switch seg {
            case .text(let s): rendered += s
            case .blank(let i): rendered += data.answers[safe: i] ?? "?"
            }
        }
        return rendered
    }

    // MARK: - Template parsing

    private enum Segment: Equatable {
        case text(String)
        case blank(Int)
    }

    private var parsedSegments: [Segment] {
        // Match {{n}} where n is 1-indexed; convert to 0-indexed for our arrays.
        let regex = try? NSRegularExpression(pattern: #"\{\{\s*(\d+)\s*\}\}"#)
        let nsTemplate = data.template as NSString
        var segments: [Segment] = []
        var cursor = 0

        guard let regex else { return [.text(data.template)] }
        let matches = regex.matches(in: data.template, range: NSRange(location: 0, length: nsTemplate.length))
        for m in matches {
            if m.range.location > cursor {
                let pre = nsTemplate.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                if !pre.isEmpty { segments.append(.text(pre)) }
            }
            let numStr = nsTemplate.substring(with: m.range(at: 1))
            if let num = Int(numStr) {
                segments.append(.blank(max(0, num - 1)))
            }
            cursor = m.range.location + m.range.length
        }
        if cursor < nsTemplate.length {
            let tail = nsTemplate.substring(from: cursor)
            if !tail.isEmpty { segments.append(.text(tail)) }
        }
        return segments
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
