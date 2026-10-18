import Foundation

/// 客户端抽象：ViewModel 只依赖它，测试用替身替换。
public protocol YuE2Servicing {
    func health() async throws -> ServerHealth
    func generate(_ request: GenerateRequest) async throws -> String
    func jobs(limit: Int) async throws -> JobListResponse
    func job(id: String) async throws -> JobDetail
    func cancel(id: String) async throws -> CancelResponse
    func audioURL(id: String) -> URL
    func streamURL(id: String) -> URL
    func scoreURL(id: String) -> URL
    /// 文件端点所需的额外 Header（给 AVPlayer / 下载用）。
    func authHeaders() -> [String: String]
}

/// YuE2 服务器 HTTP 客户端。所有错误转成中文 `APIError`。
public struct YuE2Client: YuE2Servicing {
    public var baseURL: URL
    public var apiKey: String
    public var session: URLSession
    public var timeout: TimeInterval

    public init(baseURL: URL, apiKey: String = "", session: URLSession = .shared, timeout: TimeInterval = 30) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
        self.timeout = timeout
    }

    // MARK: - URL 构造

    public func audioURL(id: String) -> URL {
        baseURL.appendingPathComponent("api/jobs/\(id)/audio")
    }

    public func streamURL(id: String) -> URL {
        baseURL.appendingPathComponent("api/jobs/\(id)/stream")
    }

    public func scoreURL(id: String) -> URL {
        baseURL.appendingPathComponent("api/jobs/\(id)/score.abc")
    }

    private func makeRequest(path: String, query: [URLQueryItem] = [], method: String = "GET") -> URLRequest {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        req.httpMethod = method
        if method == "POST" {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if !apiKey.isEmpty {
            req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        return req
    }

    public func authHeaders() -> [String: String] {
        apiKey.isEmpty ? [:] : ["X-API-Key": apiKey]
    }

    // MARK: - 请求执行

    private func run<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw APIError.network("没有收到服务器响应") }
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.http(status: http.statusCode, message: serverMessage(from: data))
            }
            do {
                return try JSONDecoder.yue2.decode(type, from: data)
            } catch {
                throw APIError.decoding
            }
        } catch let e as APIError {
            throw e
        } catch let e as URLError {
            throw APIError.network(e.yue2Reason)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }

    /// 从错误响应里取 {"error": "..."}。
    private func serverMessage(from data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = obj["error"] as? String { return msg }
        return ""
    }

    // MARK: - 端点

    public func health() async throws -> ServerHealth {
        try await run(makeRequest(path: "api/health"), as: ServerHealth.self)
    }

    public func generate(_ request: GenerateRequest) async throws -> String {
        var req = makeRequest(path: "api/generate", method: "POST")
        req.httpBody = try JSONEncoder.yue2.encode(request)
        struct Resp: Decodable { var job_id: String }
        let r: Resp = try await run(req, as: Resp.self)
        return r.job_id
    }

    public func jobs(limit: Int) async throws -> JobListResponse {
        try await run(makeRequest(path: "api/jobs", query: [URLQueryItem(name: "limit", value: "\(limit)")]),
                      as: JobListResponse.self)
    }

    public func job(id: String) async throws -> JobDetail {
        try await run(makeRequest(path: "api/jobs/\(id)"), as: JobDetail.self)
    }

    public func cancel(id: String) async throws -> CancelResponse {
        try await run(makeRequest(path: "api/jobs/\(id)/cancel", method: "POST"), as: CancelResponse.self)
    }
}

extension JSONDecoder {
    static var yue2: JSONDecoder { JSONDecoder() }
}

extension JSONEncoder {
    static var yue2: JSONEncoder { JSONEncoder() }
}
