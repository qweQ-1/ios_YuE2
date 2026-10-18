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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "ok"
        engine = try c.decodeIfPresent(EngineState.self, forKey: .engine) ?? .ready
        engineMessage = try c.decodeIfPresent(String.self, forKey: .engineMessage) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        device = try c.decodeIfPresent(String.self, forKey: .device) ?? ""
        stub = try c.decodeIfPresent(Bool.self, forKey: .stub) ?? false
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
        queueDepth = try c.decodeIfPresent(Int.self, forKey: .queueDepth) ?? 0
        activeJob = try c.decodeIfPresent(String.self, forKey: .activeJob)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(status, forKey: .status)
        try c.encode(engine, forKey: .engine)
        try c.encode(engineMessage, forKey: .engineMessage)
        try c.encode(model, forKey: .model)
        try c.encode(device, forKey: .device)
        try c.encode(stub, forKey: .stub)
        try c.encode(version, forKey: .version)
        try c.encode(queueDepth, forKey: .queueDepth)
        try c.encodeIfPresent(activeJob, forKey: .activeJob)
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
