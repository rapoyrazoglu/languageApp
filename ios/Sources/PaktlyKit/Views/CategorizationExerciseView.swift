import SwiftUI

/// Family 10 — Categorization. Two distinct UXs depending on
/// `exerciseType`:
///
/// - `oddOneOut`: tap one of N items; correct iff the tapped index equals
///   `data.oddIndex`.
/// - `categorySort`: tap an item, then tap one of the bucket headers to
///   drop it in. Each bucket records its assignments; on submit we score
///   against the declared `data.categories`.
public struct CategorizationExerciseView: View {
    public let data: CategorizationData
    public let exerciseType: ExerciseType
    public let pack: InstalledPack
    public let onAudioRequest: (URL) -> Void
    public let onFinish: (Bool) -> Void

    @State private var pickedOddIndex: Int? = nil

    /// `assignments[itemIndex] = bucketIndex` (or nil if unassigned).
    @State private var assignments: [Int?] = []
    @State private var pendingItem: Int? = nil

    @State private var submitted: Bool = false

    public init(
        data: CategorizationData,
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
                if exerciseType == .oddOneOut {
                    oddOneOutGrid
                } else {
                    categorySortLayout
                }

                if submitted {
                    ExerciseFeedbackBanner(
                        isCorrect: isCorrect,
                        correctAnswer: nil,
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
                    .disabled(!canSubmit)
                }
            }
            .padding()
        }
        .onAppear(perform: setupIfNeeded)
    }

    // MARK: - Setup

    private func setupIfNeeded() {
        if assignments.isEmpty {
            assignments = Array(repeating: nil, count: data.items.count)
        }
    }

    // MARK: - Odd-one-out

    private var oddOneOutGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(data.items.enumerated()), id: \.offset) { idx, item in
                Button {
                    if !submitted { pickedOddIndex = idx }
                } label: {
                    Text(item)
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(oddBackground(idx: idx))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(submitted)
            }
        }
    }

    private func oddBackground(idx: Int) -> Color {
        if submitted {
            if idx == data.oddIndex { return Color.green.opacity(0.18) }
            if idx == pickedOddIndex { return Color.red.opacity(0.18) }
            return Color.secondary.opacity(0.05)
        }
        return idx == pickedOddIndex ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.06)
    }

    // MARK: - Category sort

    private var categorySortLayout: some View {
        VStack(spacing: 12) {
            ForEach(Array(data.categories.enumerated()), id: \.offset) { idx, bucket in
                bucketView(idx: idx, bucket: bucket)
            }

            Divider()

            FlowLayout(spacing: 8) {
                ForEach(Array(data.items.enumerated()), id: \.offset) { idx, item in
                    if assignments[idx] == nil {
                        Text(item)
                            .font(.body)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(itemBackground(idx: idx))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture {
                                if !submitted {
                                    pendingItem = pendingItem == idx ? nil : idx
                                }
                            }
                    }
                }
            }
        }
    }

    private func bucketView(idx: Int, bucket: CategoryBucket) -> some View {
        let bucketItems = assignments.enumerated().compactMap { (i, a) in a == idx ? i : nil }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(bucket.name).font(.headline)
                Spacer()
                if submitted {
                    Image(systemName: bucketIsAllCorrect(idx: idx) ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(bucketIsAllCorrect(idx: idx) ? Color.green : Color.red)
                }
            }
            FlowLayout(spacing: 6) {
                ForEach(bucketItems, id: \.self) { itemIdx in
                    Text(data.items[itemIdx])
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(itemInBucketBackground(itemIdx: itemIdx, bucketIdx: idx))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onTapGesture {
                            if !submitted { assignments[itemIdx] = nil }
                        }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            if !submitted, let item = pendingItem {
                assignments[item] = idx
                pendingItem = nil
            }
        }
    }

    private func itemBackground(idx: Int) -> Color {
        idx == pendingItem ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08)
    }

    private func itemInBucketBackground(itemIdx: Int, bucketIdx: Int) -> Color {
        guard submitted else { return Color.accentColor.opacity(0.12) }
        return isItemCorrectInBucket(itemIdx: itemIdx, bucketIdx: bucketIdx)
            ? Color.green.opacity(0.18)
            : Color.red.opacity(0.18)
    }

    // MARK: - Logic

    private var canSubmit: Bool {
        if exerciseType == .oddOneOut { return pickedOddIndex != nil }
        return !assignments.contains(where: { $0 == nil })
    }

    private var isCorrect: Bool {
        if exerciseType == .oddOneOut {
            return pickedOddIndex != nil && pickedOddIndex == data.oddIndex
        }
        for (itemIdx, bucketIdx) in assignments.enumerated() {
            guard let bucketIdx else { return false }
            let item = data.items[itemIdx]
            guard data.categories[bucketIdx].items.contains(item) else { return false }
        }
        return true
    }

    private func bucketIsAllCorrect(idx: Int) -> Bool {
        let assigned = assignments.enumerated().filter { $0.element == idx }.map { data.items[$0.offset] }
        let expected = Set(data.categories[idx].items)
        return Set(assigned) == expected
    }

    private func isItemCorrectInBucket(itemIdx: Int, bucketIdx: Int) -> Bool {
        data.categories[bucketIdx].items.contains(data.items[itemIdx])
    }
}
