import Foundation

/// App 设置：服务器地址、API Key、默认创作模式、引导完成状态。
public final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults

    @Published public var serverAddress: String { didSet { defaults.set(serverAddress, forKey: Keys.address) } }
    @Published public var apiKey: String { didSet { defaults.set(apiKey, forKey: Keys.apiKey) } }
    @Published public var defaultCot: CotMode { didSet { defaults.set(defaultCot.rawValue, forKey: Keys.cot) } }
    @Published public var onboardingDone: Bool { didSet { defaults.set(onboardingDone, forKey: Keys.onboarding) } }

    private enum Keys {
        static let address = "yue2.serverAddress"
        static let apiKey = "yue2.apiKey"
        static let cot = "yue2.defaultCot"
        static let onboarding = "yue2.onboardingDone"
    }

    /// - Parameter suite: nil 为标准 UserDefaults；测试注入独立 suite。
    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? .standard
        self.serverAddress = self.defaults.string(forKey: Keys.address) ?? ""
        self.apiKey = self.defaults.string(forKey: Keys.apiKey) ?? ""
        if let raw = self.defaults.string(forKey: Keys.cot), let mode = CotMode(rawValue: raw) {
            self.defaultCot = mode
        } else {
            self.defaultCot = .full
        }
        self.onboardingDone = self.defaults.bool(forKey: Keys.onboarding)
    }

    public var normalizedServerURL: URL? { ServerURL.normalize(serverAddress) }

    public var isServerConfigured: Bool { normalizedServerURL != nil }

    /// 依据当前设置构造客户端。
    public func makeClient() -> YuE2Client {
        YuE2Client(baseURL: normalizedServerURL ?? URL(string: "https://invalid.local")!,
                   apiKey: apiKey)
    }
}
