import Foundation

/// 本地创作历史：只记索引（job_id + 摘要），详情永远回服务器拉取。
public struct HistoryEntry: Codable, Equatable, Identifiable {
    public var id: String           // job_id
    public var title: String        // style 摘要
    public var style: String
    public var cot: CotMode
    public var createdAt: Date
    public var lastStatus: JobStatus?
    public var audioSeconds: Double?
    /// 服务器已找不到该任务（被淘汰）时置 true。
    public var missingOnServer: Bool

    public init(id: String, title: String, style: String, cot: CotMode,
                createdAt: Date, lastStatus: JobStatus?, audioSeconds: Double? = nil) {
        self.id = id
        self.title = title
        self.style = style
        self.cot = cot
        self.createdAt = createdAt
        self.lastStatus = lastStatus
        self.audioSeconds = audioSeconds
        self.missingOnServer = false
    }
}

/// 历史记录存储：JSON 文件，原子写入。线程不安全由调用方保证（主线程使用）。
public final class HistoryStore: ObservableObject {
    private let fileURL: URL

    @Published public private(set) var entries: [HistoryEntry]

    public init(directoryURL: URL? = nil) {
        let dir = directoryURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YuE2Studio", isDirectory: true)
        self.fileURL = dir.appendingPathComponent("history.json")
        self.entries = (try? Self.load(from: fileURL)) ?? []
    }

    private static func load(from url: URL) throws -> [HistoryEntry] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([HistoryEntry].self, from: data)
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[YuE2Studio] history persist failed: \(error.localizedDescription)")
        }
    }

    public func all() -> [HistoryEntry] {
        entries.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    public func addOrUpdate(_ entry: HistoryEntry) -> HistoryEntry {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            var merged = entries[idx]
            merged.lastStatus = entry.lastStatus ?? merged.lastStatus
            if entry.audioSeconds != nil { merged.audioSeconds = entry.audioSeconds }
            entries[idx] = merged
        } else {
            entries.append(entry)
        }
        persist()
        return entries.first { $0.id == entry.id } ?? entry
    }

    public func markStatus(id: String, status: JobStatus, audioSeconds: Double? = nil, missing: Bool? = nil) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].lastStatus = status
        if let audioSeconds { entries[idx].audioSeconds = audioSeconds }
        if let missing { entries[idx].missingOnServer = missing }
        persist()
    }

    public func remove(id: String) {
        entries.removeAll { $0.id == id }
        persist()
    }

    public func clear() {
        entries.removeAll()
        persist()
    }
}
