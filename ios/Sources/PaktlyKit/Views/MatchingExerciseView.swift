import SwiftUI

/// Family 5 — Matching. Tap-to-pair UX (no drag-and-drop): the user taps a
/// tile in the left column, then a tile in the right; if both are still
/// unpaired, they connect. Audio / image variants render the corresponding
/// media inside the tile. Once every left tile has a partner, "Submit" turns
/// enabled and the view marks each pair right or wrong before continuing.
public struct MatchingExerciseView: View {
    public let data: MatchingData
    public let pack: InstalledPack
    public let onAudioRequest: (URL) -> Void
    public let onFinish: (Bool) -> Void

    /// Right indices presented to the user (shuffled once at init so the
    /// matching isn't trivial). Left side stays in declared order.
    @State private var rightOrder: [Int] = []

    /// Currently-selected tile, if any. `.left(i)` waits for a right pick;
    /// `.right(j)` waits for a left pick. Either selection clears on a second
    /// tap of the same side.
    @State private var pending: Selection? = nil

    /// userPairs[leftIndex] = rightIndex (the user's claim). Nil entries are
    /// still unpaired. After submission these are scored against
    /// `data.pairs[i].right` matching the row at `i`.
    @State private var userPairs: [Int?] = []

    @State private var submitted: Bool = false

    public init(
        data: MatchingData,
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
                HStack(alignment: .top, spacing: 12) {
                    column(items: leftItems, isLeft: true)
                    column(items: rightItems, isLeft: false)
                }

                if submitted {
                    ExerciseFeedbackBanner(
                        isCorrect: allPairsCorrect,
                        correctAnswer: nil,
                        explanation: nil
                    )
                    Button {
                        onFinish(allPairsCorrect)
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
                    .disabled(!allLeftPaired)
                }
            }
            .padding()
        }
        .onAppear(perform: setupIfNeeded)
    }

    // MARK: - Setup

    private func setupIfNeeded() {
        if userPairs.isEmpty {
            userPairs = Array(repeating: nil, count: data.pairs.count)
        }
        if rightOrder.count != data.pairs.count {
            rightOrder = Array(0..<data.pairs.count).shuffled()
        }
    }

    // MARK: - Columns

    private var leftItems: [(slotIndex: Int, media: ExerciseMedia)] {
        data.pairs.enumerated().map { ($0.offset, $0.element.left) }
    }

    private var rightItems: [(slotIndex: Int, media: ExerciseMedia)] {
        rightOrder.map { ($0, data.pairs[$0].right) }
    }

    private func column(items: [(slotIndex: Int, media: ExerciseMedia)], isLeft: Bool) -> some View {
        VStack(spacing: 8) {
            ForEach(items.indices, id: \.self) { row in
                let item = items[row]
                tile(item: item, isLeft: isLeft, displayedRow: row)
            }
        }
    }

    private func tile(
        item: (slotIndex: Int, media: ExerciseMedia),
        isLeft: Bool,
        displayedRow: Int
    ) -> some View {
        Button {
            handleTap(slotIndex: item.slotIndex, isLeft: isLeft)
        } label: {
            VStack(spacing: 4) {
                if let text = item.media.text, !text.isEmpty {
                    Text(text)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                }
                if let path = item.media.audio, let url = pack.mediaURL(forRelativePath: path) {
                    Image(systemName: "speaker.wave.2.fill")
                        .onTapGesture { onAudioRequest(url) }
                }
                if let path = item.media.image, let url = pack.mediaURL(forRelativePath: path) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFit().frame(height: 60)
                        }
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(tileBackground(slotIndex: item.slotIndex, isLeft: isLeft))
            .overlay(pairBadge(slotIndex: item.slotIndex, isLeft: isLeft))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(submitted)
    }

    @ViewBuilder
    private func pairBadge(slotIndex: Int, isLeft: Bool) -> some View {
        // Show a small numeric chip on a paired tile so the user can see
        // which left maps to which right.
        if let pairNumber = pairNumber(slotIndex: slotIndex, isLeft: isLeft) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(badgeColor(slotIndex: slotIndex, isLeft: isLeft), lineWidth: 1.5)
                VStack {
                    HStack {
                        Spacer()
                        Text("\(pairNumber)")
                            .font(.caption2.bold())
                            .padding(4)
                            .background(badgeColor(slotIndex: slotIndex, isLeft: isLeft))
                            .clipShape(Circle())
                            .foregroundStyle(.white)
                            .padding(4)
                    }
                    Spacer()
                }
            }
        }
    }

    private func tileBackground(slotIndex: Int, isLeft: Bool) -> Color {
        if submitted {
            if isCorrectFor(slotIndex: slotIndex, isLeft: isLeft) {
                return Color.green.opacity(0.12)
            }
            return Color.red.opacity(0.12)
        }
        if isPending(slotIndex: slotIndex, isLeft: isLeft) {
            return Color.accentColor.opacity(0.18)
        }
        if pairNumber(slotIndex: slotIndex, isLeft: isLeft) != nil {
            return Color.secondary.opacity(0.1)
        }
        return Color.secondary.opacity(0.06)
    }

    private func badgeColor(slotIndex: Int, isLeft: Bool) -> Color {
        if submitted {
            return isCorrectFor(slotIndex: slotIndex, isLeft: isLeft) ? .green : .red
        }
        return .accentColor
    }

    // MARK: - Pair logic

    private enum Selection: Equatable {
        case left(Int)
        case right(Int)
    }

    private func handleTap(slotIndex: Int, isLeft: Bool) {
        // Tapping an already-paired tile breaks that pair.
        if let leftIdx = leftIndex(forPaired: slotIndex, isLeft: isLeft) {
            userPairs[leftIdx] = nil
            pending = nil
            return
        }

        switch (pending, isLeft) {
        case (.left(let l), false):
            userPairs[l] = slotIndex
            pending = nil
        case (.right(let r), true):
            userPairs[slotIndex] = r
            pending = nil
        case (_, true):
            pending = pending == .left(slotIndex) ? nil : .left(slotIndex)
        case (_, false):
            pending = pending == .right(slotIndex) ? nil : .right(slotIndex)
        }
    }

    private func leftIndex(forPaired slotIndex: Int, isLeft: Bool) -> Int? {
        if isLeft {
            return userPairs[slotIndex] != nil ? slotIndex : nil
        }
        return userPairs.firstIndex(of: slotIndex)
    }

    private func isPending(slotIndex: Int, isLeft: Bool) -> Bool {
        switch pending {
        case .left(let i): return isLeft && i == slotIndex
        case .right(let j): return !isLeft && j == slotIndex
        case .none: return false
        }
    }

    private func pairNumber(slotIndex: Int, isLeft: Bool) -> Int? {
        if isLeft {
            return userPairs[slotIndex] != nil ? slotIndex + 1 : nil
        }
        if let leftIdx = userPairs.firstIndex(of: slotIndex) {
            return leftIdx + 1
        }
        return nil
    }

    private func isCorrectFor(slotIndex: Int, isLeft: Bool) -> Bool {
        if isLeft {
            return userPairs[slotIndex] == slotIndex
        }
        guard let leftIdx = userPairs.firstIndex(of: slotIndex) else { return false }
        return leftIdx == slotIndex
    }

    private var allLeftPaired: Bool {
        !userPairs.contains(where: { $0 == nil })
    }

    private var allPairsCorrect: Bool {
        for (left, right) in userPairs.enumerated() {
            if right != left { return false }
        }
        return true
    }
}
