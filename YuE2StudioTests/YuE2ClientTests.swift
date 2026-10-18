import XCTest
@testable import YuE2Studio

// MARK: - 请求桩

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let (resp, data) = handler(request)
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private let stubURL = URL(string: "https://stub.local/")!

private func jsonResponse(_ obj: Any, status: Int = 200) -> (HTTPURLResponse, Data) {
    (HTTPURLResponse(url: stubURL, statusCode: status, httpVersion: "1.1", headerFields: nil)!,
     try! JSONSerialization.data(withJSONObject: obj))
}

private func rawResponse(_ str: String, status: Int = 200) -> (HTTPURLResponse, Data) {
    (HTTPURLResponse(url: stubURL, statusCode: status, httpVersion: "1.1", headerFields: nil)!,
     Data(str.utf8))
}

final class YuE2ClientTests: XCTestCase {
    private var client: YuE2Client!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        client = YuE2Client(baseURL: URL(string: "https://stub.test")!,
                            apiKey: "secret-key",
                            session: URLSession(configuration: config))
        StubURLProtocol.handler = nil
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testURLsUseBaseAndJobID() {
        XCTAssertEqual(client.audioURL(id: "abc").absoluteString, "https://stub.test/api/jobs/abc/audio")
        XCTAssertEqual(client.streamURL(id: "abc").absoluteString, "https://stub.test/api/jobs/abc/stream")
        XCTAssertEqual(client.scoreURL(id: "abc").absoluteString, "https://stub.test/api/jobs/abc/score.abc")
        XCTAssertEqual(client.authHeaders(), ["X-API-Key": "secret-key"])
    }

    func testHealthDecodesAndSendsKey() async throws {
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "X-API-Key"), "secret-key")
            XCTAssertEqual(req.url?.path, "/api/health")
            return jsonResponse(["status": "ok", "engine": "ready", "model": "m-a-p/YuE2-3B",
                                 "device": "cuda", "stub": false, "version": "1.0.0", "queue_depth": 0])
        }
        let h = try await client.health()
        XCTAssertEqual(h.engine, .ready)
        XCTAssertEqual(h.model, "m-a-p/YuE2-3B")
    }

    func testGeneratePostsBodyAndReturnsJobID() async throws {
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.url?.path, "/api/generate")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
            guard let bodyData = req.httpBody else {
                XCTFail("请求体丢失")
                return jsonResponse(["job_id": "missing"], status: 500)
            }
            let body = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] ?? [:]
            XCTAssertEqual(body["style"] as? String, "city pop")
            XCTAssertEqual(body["lyrics"] as? String, "[Verse]")
            XCTAssertEqual(body["cot"] as? String, "full")
            XCTAssertNil(body["abc"])
            return jsonResponse(["job_id": "20261018-x1", "status": "queued"])
        }
        let id = try await client.generate(GenerateRequest(style: "city pop", lyrics: "[Verse]"))
        XCTAssertEqual(id, "20261018-x1")
    }

    func testHTTPErrorMapsServerMessage() async {
        StubURLProtocol.handler = { _ in jsonResponse(["error": "风格或歌词不能为空"], status: 400) }
        do {
            _ = try await client.jobs(limit: 10)
            XCTFail("应当抛错")
        } catch let e as APIError {
            XCTAssertEqual(e, APIError.http(status: 400, message: "风格或歌词不能为空"))
            XCTAssertEqual(e.message, "风格或歌词不能为空")
        } catch {
            XCTFail("错误类型不对：\(error)")
        }
    }

    func testJobsAppendsLimitQuery() async throws {
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.path, "/api/jobs")
            XCTAssertEqual(req.url?.query, "limit=50")
            return jsonResponse(["items": [], "total": 0])
        }
        let r = try await client.jobs(limit: 50)
        XCTAssertEqual(r.items.count, 0)
    }

    func testBadJSONBecomesDecodingError() async {
        StubURLProtocol.handler = { _ in rawResponse("这不是 JSON", status: 200) }
        do {
            _ = try await client.health()
            XCTFail("应当抛错")
        } catch let e as APIError {
            XCTAssertEqual(e, .decoding)
        } catch {
            XCTFail("错误类型不对：\(error)")
        }
    }

    func testServerErrorWithoutMessageFallsBackToGeneric() async {
        StubURLProtocol.handler = { _ in jsonResponse([:], status: 503) }
        do {
            _ = try await client.cancel(id: "x")
            XCTFail("应当抛错")
        } catch let e as APIError {
            if case .http(let status, let msg) = e {
                XCTAssertEqual(status, 503)
                XCTAssertEqual(msg, "")  // 原始 message 为空
                XCTAssertEqual(e.message, "服务器返回错误（HTTP 503）")  // 兜底文案
            } else {
                XCTFail("错误类型不对：\(e)")
            }
        } catch {
            XCTFail("错误类型不对：\(error)")
        }
    }

    func testTransportFailureMapsToNetworkMessage() async {
        StubURLProtocol.handler = nil  // handler 缺失 → didFailWithError(.badURL)
        do {
            _ = try await client.health()
            XCTFail("应当抛错")
        } catch let e as APIError {
            guard case .network = e else { return XCTFail("错误类型不对：\(e)") }
        } catch {
            XCTFail("错误类型不对：\(error)")
        }
    }
}
