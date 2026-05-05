import Foundation

// MARK: - Lesson

/// One lesson file: an ordered sequence of content blocks.
public struct Lesson: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let description: String?
    public let estimatedMinutes: Int?
    public let prerequisites: [String]
    public let blocks: [Block]

    public init(
        id: String,
        title: String,
        description: String? = nil,
        estimatedMinutes: Int? = nil,
        prerequisites: [String] = [],
        blocks: [Block]
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.estimatedMinutes = estimatedMinutes
        self.prerequisites = prerequisites
        self.blocks = blocks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.estimatedMinutes = try c.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        self.prerequisites = try c.decodeIfPresent([String].self, forKey: .prerequisites) ?? []
        self.blocks = try c.decode([Block].self, forKey: .blocks)
    }
}
