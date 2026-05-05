import SwiftUI

/// Family 7 — WordOrder. Tap a tile in the pool to add it to the answer
/// row; tap a tile in the answer row to send it back to the pool. Once
/// every required slot is filled, "Submit" is enabled. `letterScramble`
/// reuses the same view — the only difference is that tiles are letters,
/// not words; we render with a different font / spacing accordingly.
public struct WordOrderExerciseView: View {
    public let data: WordOrderData
    public let exerciseType: ExerciseType
    public let pack: InstalledPack
    public let onAudioRequest: (URL) -> Void
    public let onFinish: (Bool) -> Void

    /// Visible tiles in shuffled order; each entry is the original tile
    /// index (or `tiles.count + offset` if it's a distractor).
    @State private var pool: [TilePiece] = []
    @State private var selected: [TilePiece] = []
    @State private var submitted: Bool = false

    public init(
        data: WordOrderData,
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
                if let translation = data.translation, !translation.isEmpty {
                    Text(translation)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                answerRow

                Divider()

                poolView

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
                    .disabled(selected.count != data.correctOrder.count)
                }
            }
            .padding()
        }
        .onAppear(perform: setupIfNeeded)
    }

    // MARK: - Sub-views

    private var answerRow: some View {
        FlowLayout(spacing: 8) {
            ForEach(selected, id: \.id) { piece in
                tileView(piece, removable: !submitted)
                    .onTapGesture { if !submitted { sendBackToPool(piece) } }
            }
            if selected.isEmpty {
                Text(" ")
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(8)
        .frame(minHeight: 56)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var poolView: some View {
        FlowLayout(spacing: 8) {
            ForEach(pool, id: \.id) { piece in
                tileView(piece, removable: false)
                    .onTapGesture { if !submitted { addToAnswer(piece) } }
            }
        }
    }

    private func tileView(_ piece: TilePiece, removable: Bool) -> some View {
        Text(piece.text)
            .font(exerciseType == .letterScramble ? .title2 : .body)
            .padding(.horizontal, exerciseType == .letterScramble ? 14 : 12)
            .padding(.vertical, 8)
            .background(tileBackground(piece))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func tileBackground(_ piece: TilePiece) -> Color {
        if submitted {
            if let i = selected.firstIndex(where: { $0.id == piece.id }) {
                return correctOrder[safe: i] == piece.tileIndex
                    ? Color.green.opacity(0.18)
                    : Color.red.opacity(0.18)
            }
        }
        return Color.accentColor.opacity(0.12)
    }

    // MARK: - Setup + interactions

    private func setupIfNeeded() {
        if !pool.isEmpty || !selected.isEmpty { return }
        var pieces: [TilePiece] = []
        for (i, t) in data.tiles.enumerated() {
            pieces.append(TilePiece(id: UUID(), tileIndex: i, text: t, isDistractor: false))
        }
        for (i, t) in data.distractors.enumerated() {
            pieces.append(TilePiece(id: UUID(), tileIndex: data.tiles.count + i, text: t, isDistractor: true))
        }
        pool = pieces.shuffled()
    }

    private func addToAnswer(_ piece: TilePiece) {
        guard let idx = pool.firstIndex(where: { $0.id == piece.id }) else { return }
        pool.remove(at: idx)
        selected.append(piece)
    }

    private func sendBackToPool(_ piece: TilePiece) {
        guard let idx = selected.firstIndex(where: { $0.id == piece.id }) else { return }
        selected.remove(at: idx)
        pool.append(piece)
    }

    // MARK: - Logic

    private var correctOrder: [Int] { data.correctOrder }

    private var isCorrect: Bool {
        guard selected.count == correctOrder.count else { return false }
        for (i, piece) in selected.enumerated() {
            if piece.tileIndex != correctOrder[i] { return false }
        }
        return true
    }

    private var correctSentence: String {
        correctOrder.compactMap { data.tiles[safe: $0] }.joined(
            separator: exerciseType == .letterScramble ? "" : " "
        )
    }
}

private struct TilePiece: Equatable, Identifiable {
    let id: UUID
    let tileIndex: Int
    let text: String
    let isDistractor: Bool
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Tiny flow layout

/// Wrap-style layout that flows children left-to-right and breaks to the
/// next line when out of horizontal room. SwiftUI doesn't ship one, and we
/// don't want a third-party dep for one screen.
struct FlowLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat = 8) { self.spacing = spacing }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, totalWidth: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x + size.width)
            x += size.width + spacing
        }
        return CGSize(width: totalWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        let maxX = bounds.maxX

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
