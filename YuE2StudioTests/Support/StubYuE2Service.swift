import Foundation
@testable import YuE2Studio

/// 可编排的假服务：记录调用、注入响应与错误。
final class StubYuE2Service: YuE2Servicing {
    var healthResult: Result<ServerHealth, Error> = .success(ServerHealth())
    var generateResult: Result<String, Error> = .success("job-1")
    var jobsResult: Result<JobListResponse, Error> = .success(JobListResponse(items: [], total: 0))
    var jobResultByID: [String: Result<JobDetail, Error>] = [:]
    var cancelResult: Result<CancelResponse, Error> = .success(CancelResponse(id: "job-1", status: "cancelled"))

    var generateCalls: [GenerateRequest] = []
    var cancelCalls: [String] = []

    func health() async throws -> ServerHealth {
        try healthResult.get()
    }

    func generate(_ request: GenerateRequest) async throws -> String {
        generateCalls.append(request)
        return try generateResult.get()
    }

    func jobs(limit: Int) async throws -> JobListResponse {
        try jobsResult.get()
    }

    func job(id: String) async throws -> JobDetail {
        guard let r = jobResultByID[id] else { throw APIError.http(status: 404, message: "任务不存在") }
        return try r.get()
    }

    func cancel(id: String) async throws -> CancelResponse {
        cancelCalls.append(id)
        return try cancelResult.get()
    }

    func audioURL(id: String) -> URL { URL(string: "https://stub.local/api/jobs/\(id)/audio")! }
    func streamURL(id: String) -> URL { URL(string: "https://stub.local/api/jobs/\(id)/stream")! }
    func scoreURL(id: String) -> URL { URL(string: "https://stub.local/api/jobs/\(id)/score.abc")! }
    func authHeaders() -> [String: String] { ["X-API-Key": "k"] }
}
