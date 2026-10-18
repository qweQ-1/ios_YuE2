import Foundation

/// POST /api/generate 请求体。
public struct GenerateRequest: Codable, Equatable {
    public var style: String
    public var lyrics: String
    public var cot: CotMode
    public var abc: String?
    public var seed: Int?
    public var guidance: Double?

    enum CodingKeys: String, CodingKey {
        case style, lyrics, cot, abc, seed, guidance
    }

    public init(style: String, lyrics: String, cot: CotMode = .full,
                abc: String? = nil, seed: Int? = nil, guidance: Double? = nil) {
        self.style = style
        self.lyrics = lyrics
        self.cot = cot
        self.abc = abc
        self.seed = seed
        self.guidance = guidance
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(style, forKey: .style)
        try c.encode(lyrics, forKey: .lyrics)
        try c.encode(cot, forKey: .cot)
        if let abc, !abc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try c.encode(abc, forKey: .abc)
        }
        if let seed { try c.encode(seed, forKey: .seed) }
        if let guidance { try c.encode(guidance, forKey: .guidance) }
    }
}
