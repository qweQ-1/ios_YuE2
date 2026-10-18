import Foundation

/// 任务列表条目（合并服务器列表与本地历史）。
public struct JobListItem: Identifiable, Equatable {
    public var id: String
    public var title: String
    public var cot: CotMode
    public var status: JobStatus
    public var createdAt: String
    public var audioSeconds: Double?
    public var seed: Int?
    /// true 表示本地有记录但服务器已无此任务。
    public var missing: Bool

    public init(id: String, title: String, cot: CotMode, status: JobStatus, createdAt: String,
                audioSeconds: Double?, seed: Int?, missing: Bool = false) {
        self.id = id
        self.title = title
        self.cot = cot
        self.status = status
        self.createdAt = createdAt
        self.audioSeconds = audioSeconds
        self.seed = seed
        self.missing = missing
    }
}

/// 任务列表 ViewModel：合并服务器数据与本地历史。
@MainActor
public final class JobsViewModel: ObservableObject {
    @Published public private(set) var items: [JobListItem] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public private(set) var hasActive = false

    private let clientProvider: () -> YuE2Servicing
    private let history: HistoryStore
    private var pollTask: Task<Void, Never>?

    public init(clientProvider: @escaping () -> YuE2Servicing, history: HistoryStore) {
        self.clientProvider = clientProvider
        self.history = history
    }

    private var service: YuE2Servicing { clientProvider() }

    // MARK: 拉取与合并

    public func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await service.jobs(limit: 50)
            apply(serverItems: resp.items)
            errorMessage = nil
        } catch let e as APIError {
            errorMessage = e.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 合并策略：服务器条目为主体；本地历史里的旧任务若服务器已没有，标「已失效」仍展示。
    private func apply(serverItems: [JobSummary]) {
        var serverByID: [String: JobSummary] = [:]
        for s in serverItems { serverByID[s.id] = s }

        var merged: [JobListItem] = serverItems.map { s in
            history.markStatus(id: s.id, status: s.status, audioSeconds: s.audioSeconds)
            return JobListItem(id: s.id, title: Formatters.shortTitle(from: s.style), cot: s.cot,
                               status: s.status, createdAt: s.createdAt,
                               audioSeconds: s.audioSeconds, seed: s.seed)
        }

        for entry in history.all() where serverByID[entry.id] == nil {
            let status = entry.lastStatus ?? .queued
            merged.append(JobListItem(id: entry.id, title: entry.title, cot: entry.cot, status: status,
                                      createdAt: ISO8601DateFormatter().string(from: entry.createdAt),
                                      audioSeconds: entry.audioSeconds, seed: nil, missing: true))
            history.markStatus(id: entry.id, status: status, missing: true)
        }

        merged.sort { a, b in
            if a.missing != b.missing { return !a.missing }
            return a.createdAt > b.createdAt
        }
        items = merged
        hasActive = merged.contains { $0.status.isActive && !$0.missing }
    }

    // MARK: 轮询

    public func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if Task.isCancelled { return }
                guard let self, self.hasActive else { continue }
                await self.refresh()
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func cancel(id: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.service.cancel(id: id)
                await self.refresh()
            } catch let e as APIError {
                self.errorMessage = e.message
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
