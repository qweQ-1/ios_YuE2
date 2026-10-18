import Foundation

/// 任务详情 ViewModel：轮询进度、取消、拉乐谱、复用参数。
public final class JobDetailViewModel: ObservableObject {
    @Published public private(set) var detail: JobDetail?
    @Published public private(set) var score: String?
    @Published public var isLoading = false
    @Published public var errorMessage: String?

    public let jobId: String

    private let clientProvider: () -> YuE2Servicing
    private let history: HistoryStore
    private var pollTask: Task<Void, Never>?

    public init(jobId: String, clientProvider: @escaping () -> YuE2Servicing, history: HistoryStore) {
        self.jobId = jobId
        self.clientProvider = clientProvider
        self.history = history
    }

    private var service: YuE2Servicing { clientProvider() }

    public var isActive: Bool { detail?.status.isActive ?? false }

    // MARK: 加载

    @MainActor
    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let d = try await service.job(id: jobId)
            detail = d
            errorMessage = nil
            if d.status == .succeeded {
                history.markStatus(id: jobId, status: .succeeded, audioSeconds: d.result?.audioSeconds)
                if score == nil { score = try? await loadScore() }
            } else if !d.status.isActive {
                history.markStatus(id: jobId, status: d.status)
            }
        } catch let e as APIError {
            if case .http(status: 404, _) = e {
                history.markStatus(id: jobId, status: .failed, missing: true)
                errorMessage = "这条任务在服务器上已不存在（可能已被清理）"
                detail = nil
            } else {
                errorMessage = e.message
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadScore() async throws -> String {
        let url = service.scoreURL(id: jobId)
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        for (k, v) in service.authHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(status: http.statusCode, message: "")
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: 轮询与取消

    public func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if Task.isCancelled { return }
                guard let self, self.isActive else { continue }
                await self.load()
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    @MainActor
    public func cancelJob() {
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.service.cancel(id: self.jobId)
                await self.load()
            } catch let e as APIError {
                self.errorMessage = e.message
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// 用当前任务的参数重新创作（返回 nil 表示详情还没加载或参数缺失）。
    public func makeRetryRequest() -> GenerateRequest? {
        guard let d = detail,
              let style = d.paramsStyle, let lyrics = d.paramsLyrics, let cot = d.paramsCot else { return nil }
        return GenerateRequest(style: style, lyrics: lyrics, cot: cot,
                               abc: d.paramsAbc, seed: d.paramsSeed, guidance: d.paramsGuidance)
    }
}
