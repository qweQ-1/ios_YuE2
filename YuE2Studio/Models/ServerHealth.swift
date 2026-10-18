import Foundation

/// GET /api/health 响应。
public struct ServerHealth: Codable, Equatable {
    public enum EngineState: String, Codable {
        case ready
        case loading
        case error
    }

    public var status: String
    public var engine: EngineState
    public var engineMessage: String
    public var model: String
    public var device: String
    public var stub: Bool
    public var version: String
    public var queueDepth: Int
    public var activeJob: String?

    enum CodingKeys: String, CodingKey {
        case status, engine, model, device, stub, version
        case engineMessage = "engine_message"
        case queueDepth = "queue_depth"
        case activeJob = "active_job"
    }

    public init(status: String = "ok", engine: EngineState = .ready, engineMessage: String = "",
                model: String = "", device: String = "", stub: Bool = false, version: String = "",
                queueDepth: Int = 0, activeJob: String? = nil) {
        self.status = status
        self.engine = engine
        self.engineMessage = engineMessage
        self.model = model
        self.device = device
        self.stub = stub
        self.version = version
        self.queueDepth = queueDepth
        self.activeJob = activeJob
    }

    /// 一句话状态摘要（设置页展示）。
    public var summaryText: String {
        switch engine {
        case .ready:
            var s = stub ? "Stub 演示模式（未加载真模型）" : "模型就绪 · \(model) · \(device)"
            if queueDepth > 0 { s += " · 队列 \(queueDepth)" }
            return s
        case .loading:
            return engineMessage.isEmpty ? "模型加载中…" : "模型加载中：\(engineMessage)"
        case .error:
            return engineMessage.isEmpty ? "引擎异常" : "引擎异常：\(engineMessage)"
        }
    }
}
