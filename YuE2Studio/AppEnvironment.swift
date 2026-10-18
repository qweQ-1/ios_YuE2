import SwiftUI

/// 全局装配：设置 + 客户端 + 播放器 + 本地历史，以及懒加载的全局 ViewModel。
public final class AppEnvironment: ObservableObject {
    public let settings: SettingsStore
    public let history: HistoryStore
    public let player: AudioPlayerService

    private var storedClient: YuE2Client?

    public init(settings: SettingsStore? = nil, history: HistoryStore? = nil) {
        self.settings = settings ?? SettingsStore()
        self.history = history ?? HistoryStore()
        self.player = AudioPlayerService()
    }

    /// 当前客户端：服务器地址或 Key 变化时自动重建。
    public func client() -> YuE2Client {
        let url = settings.normalizedServerURL ?? URL(string: "https://invalid.local")!
        if let storedClient, storedClient.baseURL == url, storedClient.apiKey == settings.apiKey {
            return storedClient
        }
        let c = YuE2Client(baseURL: url, apiKey: settings.apiKey)
        storedClient = c
        return c
    }

    // MARK: - 全局 ViewModel（惰性、稳定实例）

    public lazy var createSongViewModel: CreateSongViewModel = {
        CreateSongViewModel(clientProvider: { [weak self] in self?.client() ?? DeadClient() }, history: history)
    }()

    public lazy var jobsViewModel: JobsViewModel = {
        JobsViewModel(clientProvider: { [weak self] in self?.client() ?? DeadClient() }, history: history)
    }()

    public func makeJobDetailViewModel(jobId: String) -> JobDetailViewModel {
        JobDetailViewModel(jobId: jobId, clientProvider: { [weak self] in self?.client() ?? DeadClient() }, history: history)
    }
}

/// 未配置服务器时的占位服务，所有调用抛出 invalidServer。
struct DeadClient: YuE2Servicing {
    func health() async throws -> ServerHealth { throw APIError.invalidServer }
    func generate(_ request: GenerateRequest) async throws -> String { throw APIError.invalidServer }
    func jobs(limit: Int) async throws -> JobListResponse { throw APIError.invalidServer }
    func job(id: String) async throws -> JobDetail { throw APIError.invalidServer }
    func cancel(id: String) async throws -> CancelResponse { throw APIError.invalidServer }
    func audioURL(id: String) -> URL { URL(string: "https://invalid.local")! }
    func streamURL(id: String) -> URL { URL(string: "https://invalid.local")! }
    func scoreURL(id: String) -> URL { URL(string: "https://invalid.local")! }
    func authHeaders() -> [String: String] { [:] }
}
