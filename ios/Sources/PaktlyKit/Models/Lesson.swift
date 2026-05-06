import Foundation

// MARK: - Lesson

/// One lesson file: an ordered sequence of content blocks.
///
/// Schema 1.2.0+ adds the optional mock-exam fields (`examMode`, `passingScore`,
/// `timeLimit`, `drawsFrom`). When `examMode` is `true`, the lesson runner
/// treats the lesson as an assessment: hint affordances are disabled, only
/// one attempt is allowed, and pack progress doesn't reach 100% until the
/// learner clears `passingScore` (defaults to 0.8 if unset).
public struct Lesson: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let description: String?
    public let estimatedMinutes: Int?
    public let prerequisites: [String]
    public let blocks: [Block]

    // Schema 1.2.0+ — mock exam fields
    public let examMode: Bool
    public let passingScore: Double?
    public let timeLimit: Int?
    public let drawsFrom: [String]

    /// Default passing score applied when `examMode` is `true` but
    /// `passingScore` was omitted from the lesson JSON.
    public static let defaultPassingScore: Double = 0.8

    /// Effective passing score for an exam lesson — uses `passingScore` if
    /// declared, otherwise the default. Returns `nil` when this is not an
    /// exam lesson.
    public var effectivePassingScore: Double? {
        guard examMode else { return nil }
        return passingScore ?? Self.defaultPassingScore
    }

    public init(
        id: String,
        title: String,
        description: String? = nil,
        estimatedMinutes: Int? = nil,
        prerequisites: [String] = [],
        blocks: [Block],
        examMode: Bool = false,
        passingScore: Double? = nil,
        timeLimit: Int? = nil,
        drawsFrom: [String] = []
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.estimatedMinutes = estimatedMinutes
        self.prerequisites = prerequisites
        self.blocks = blocks
        self.examMode = examMode
        self.passingScore = passingScore
        self.timeLimit = timeLimit
        self.drawsFrom = drawsFrom
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.estimatedMinutes = try c.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        self.prerequisites = try c.decodeIfPresent([String].self, forKey: .prerequisites) ?? []
        self.blocks = try c.decode([Block].self, forKey: .blocks)
        self.examMode = try c.decodeIfPresent(Bool.self, forKey: .examMode) ?? false
        self.passingScore = try c.decodeIfPresent(Double.self, forKey: .passingScore)
        self.timeLimit = try c.decodeIfPresent(Int.self, forKey: .timeLimit)
        self.drawsFrom = try c.decodeIfPresent([String].self, forKey: .drawsFrom) ?? []
    }
}
