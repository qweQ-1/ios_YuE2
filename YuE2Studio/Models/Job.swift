import Foundation

/// 任务状态。
public enum JobStatus: String, Codable {
    case queued
    case running
    case succeeded
    case failed
    case cancelled

    public var isActive: Bool { self == .queued || self == .running }

    public var label: String {
        switch self {
        case .queued: return "排队中"
        case .running: return "创作中"
        case .succeeded: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }
}

/// 阶段（progress.phase）。
public enum JobPhase: String, Codable {
    case queued
    case planning
    case semantic
    case synthesizing
    case decoding
    case done

    public var label: String {
        switch self {
        case .queued: return "排队中"
        case .planning: return "规划乐谱"
        case .semantic: return "谱写旋律"
        case .synthesizing: return "合成音色"
        case .decoding: return "渲染音频"
        case .done: return "完成"
        }
    }
}

public struct JobProgress: Codable, Equatable {
    public var phase: JobPhase
    public var message: String
    public var fraction: Double?
    public var tokens: Int?

    enum CodingKeys: String, CodingKey {
        case phase, message, fraction, tokens
    }

    public init(phase: JobPhase, message: String = "", fraction: Double? = nil, tokens: Int? = nil) {
        self.phase = phase
        self.message = message
        self.fraction = fraction
        self.tokens = tokens
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = try c.decodeIfPresent(JobPhase.self, forKey: .phase) ?? .queued
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        fraction = try c.decodeIfPresent(Double.self, forKey: .fraction)
        tokens = try c.decodeIfPresent(Int.self, forKey: .tokens)
    }
}

public struct JobTiming: Codable, Equatable {
    public var abcSeconds: Double?
    public var semanticSeconds: Double?
    public var narSeconds: Double?
    public var vaeSeconds: Double?
    public var e2eSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case abcSeconds = "abc_seconds"
        case semanticSeconds = "semantic_seconds"
        case narSeconds = "nar_seconds"
        case vaeSeconds = "vae_seconds"
        case e2eSeconds = "e2e_seconds"
    }
}

public struct JobResult: Codable, Equatable {
    public var audioSeconds: Double
    public var sampleRate: Int
    public var truncatedAbc: Bool
    public var truncatedSemantic: Bool
    public var timing: JobTiming?
    public var identity: String?

    enum CodingKeys: String, CodingKey {
        case audioSeconds = "audio_seconds"
        case sampleRate = "sample_rate"
        case truncated, timing, identity
    }

    enum TruncatedKeys: String, CodingKey {
        case abc, semantic
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        audioSeconds = try c.decodeIfPresent(Double.self, forKey: .audioSeconds) ?? 0
        sampleRate = try c.decodeIfPresent(Int.self, forKey: .sampleRate) ?? 48000
        if let t = try c.decodeIfPresent([String: Bool].self, forKey: .truncated) {
            truncatedAbc = t["abc"] ?? false
            truncatedSemantic = t["semantic"] ?? false
        } else {
            truncatedAbc = false
            truncatedSemantic = false
        }
        timing = try c.decodeIfPresent(JobTiming.self, forKey: .timing)
        identity = try c.decodeIfPresent(String.self, forKey: .identity)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(audioSeconds, forKey: .audioSeconds)
        try c.encode(sampleRate, forKey: .sampleRate)
        try c.encode(["abc": truncatedAbc, "semantic": truncatedSemantic], forKey: .truncated)
        try c.encodeIfPresent(timing, forKey: .timing)
        try c.encodeIfPresent(identity, forKey: .identity)
    }
}

public struct JobURLs: Codable, Equatable {
    public var audio: String
    public var stream: String
    public var score: String
}

/// GET /api/jobs/{id} 详情。
public struct JobDetail: Codable, Equatable, Identifiable {
    public var id: String
    public var status: JobStatus
    public var createdAt: String
    public var updatedAt: String
    public var progress: JobProgress
    public var error: String?
    public var result: JobResult?
    public var urls: JobURLs
    public var paramsStyle: String?
    public var paramsLyrics: String?
    public var paramsCot: CotMode?
    public var paramsAbc: String?
    public var paramsSeed: Int?
    public var paramsGuidance: Double?

    enum CodingKeys: String, CodingKey {
        case id, status, progress, error, result, urls, params
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    enum ParamsKeys: String, CodingKey {
        case style, lyrics, cot, abc, seed, guidance
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        status = try c.decodeIfPresent(JobStatus.self, forKey: .status) ?? .failed
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        progress = try c.decodeIfPresent(JobProgress.self, forKey: .progress)
            ?? JobProgress(phase: status == .succeeded ? .done : .queued, message: "")
        error = try c.decodeIfPresent(String.self, forKey: .error)
        result = try c.decodeIfPresent(JobResult.self, forKey: .result)
        urls = try c.decodeIfPresent(JobURLs.self, forKey: .urls)
            ?? JobURLs(audio: "/api/jobs/\(id)/audio", stream: "/api/jobs/\(id)/stream", score: "/api/jobs/\(id)/score.abc")
        let p = try c.decodeIfPresent([String: JSONAny].self, forKey: .params) ?? [:]
        paramsStyle = p["style"]?.stringValue
        paramsLyrics = p["lyrics"]?.stringValue
        paramsCot = (p["cot"]?.stringValue).flatMap(CotMode.init(rawValue:))
        paramsAbc = p["abc"]?.stringValue
        paramsSeed = p["seed"]?.intValue
        paramsGuidance = p["guidance"]?.doubleValue
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(status, forKey: .status)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(progress, forKey: .progress)
        try c.encodeIfPresent(error, forKey: .error)
        try c.encodeIfPresent(result, forKey: .result)
        try c.encode(urls, forKey: .urls)
    }
}

/// GET /api/jobs 列表项。
public struct JobSummary: Codable, Equatable, Identifiable {
    public var id: String
    public var status: JobStatus
    public var createdAt: String
    public var style: String
    public var lyricsExcerpt: String
    public var cot: CotMode
    public var audioSeconds: Double?
    public var seed: Int?

    enum CodingKeys: String, CodingKey {
        case id, status, style, cot, seed
        case createdAt = "created_at"
        case lyricsExcerpt = "lyrics_excerpt"
        case audioSeconds = "audio_seconds"
    }

    public init(id: String, status: JobStatus, createdAt: String, style: String,
                lyricsExcerpt: String, cot: CotMode, audioSeconds: Double?, seed: Int?) {
        self.id = id
        self.status = status
        self.createdAt = createdAt
        self.style = style
        self.lyricsExcerpt = lyricsExcerpt
        self.cot = cot
        self.audioSeconds = audioSeconds
        self.seed = seed
    }
}

public struct JobListResponse: Codable {
    public var items: [JobSummary]
    public var total: Int

    public init(items: [JobSummary], total: Int) {
        self.items = items
        self.total = total
    }
}

public struct CancelResponse: Codable {
    public var id: String
    public var status: String
}
