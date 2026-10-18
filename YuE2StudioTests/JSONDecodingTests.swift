import XCTest
@testable import YuE2Studio

final class JSONDecodingTests: XCTestCase {
    func testHealthDecoding() throws {
        let json = """
        {"status":"ok","engine":"loading","engine_message":"Resolving model files","model":"m-a-p/YuE2-3B",
         "device":"cuda","stub":false,"version":"1.0.0","queue_depth":2,"active_job":"job-9"}
        """
        let h = try JSONDecoder.yue2.decode(ServerHealth.self, from: Data(json.utf8))
        XCTAssertEqual(h.engine, .loading)
        XCTAssertEqual(h.queueDepth, 2)
        XCTAssertEqual(h.activeJob, "job-9")
        XCTAssertFalse(h.stub)
    }

    func testJobDetailParamsTolerantDecoding() throws {
        let d = Fixtures.detail()
        XCTAssertEqual(d.id, "job-1")
        XCTAssertEqual(d.status, .running)
        XCTAssertEqual(d.progress.phase, .planning)
        XCTAssertEqual(d.progress.tokens, 12)
        XCTAssertEqual(d.paramsStyle, "English, warm piano pop")
        XCTAssertEqual(d.paramsCot, .full)
        XCTAssertEqual(d.paramsSeed, 42)
        XCTAssertNil(d.paramsGuidance)
        XCTAssertNil(d.result)
    }

    func testDoneDetailDecoding() throws {
        let d = Fixtures.doneDetail()
        XCTAssertEqual(d.status, .succeeded)
        XCTAssertEqual(d.result?.audioSeconds ?? 0, 182.4, accuracy: 0.01)
        XCTAssertEqual(d.result?.sampleRate, 48000)
        XCTAssertTrue(d.result?.truncatedSemantic ?? false)
        XCTAssertFalse(d.result?.truncatedAbc ?? true)
        XCTAssertEqual(d.result?.timing?.narSeconds ?? 0, 120.5, accuracy: 0.01)
    }

    func testMinimalDetailUsesDefaults() throws {
        // 缺 progress/urls 时用兜底值，不让整个详情解析失败。
        let json = """
        {"id":"x","status":"succeeded","created_at":"2026-10-18T07:30:00Z"}
        """
        let d = try JSONDecoder.yue2.decode(JobDetail.self, from: Data(json.utf8))
        XCTAssertEqual(d.progress.phase, .done)
        XCTAssertEqual(d.urls.score, "/api/jobs/x/score.abc")
    }

    func testJobListDecoding() throws {
        let json = """
        {"items":[{"id":"a","status":"failed","created_at":"2026-10-18T07:30:00Z","style":"s","lyrics_excerpt":"l","cot":"off","audio_seconds":null,"seed":null}],"total":1}
        """
        let r = try JSONDecoder.yue2.decode(JobListResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.items.count, 1)
        XCTAssertEqual(r.items[0].status, .failed)
        XCTAssertEqual(r.items[0].cot, .off)
        XCTAssertNil(r.items[0].audioSeconds)
    }

    func testGenerateRequestOmitsEmptyOptionalFields() throws {
        let req = GenerateRequest(style: "s", lyrics: "l", cot: .melody, abc: nil)
        let data = try JSONEncoder.yue2.encode(req)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNil(obj["abc"])
        XCTAssertNil(obj["seed"])
        XCTAssertEqual(obj["cot"] as? String, "melody")

        let withABC = GenerateRequest(style: "s", lyrics: "l", cot: .full, abc: "X:1\nK:C", seed: 7, guidance: 1.2)
        let data2 = try JSONEncoder.yue2.encode(withABC)
        let obj2 = try JSONSerialization.jsonObject(with: data2) as! [String: Any]
        XCTAssertEqual(obj2["abc"] as? String, "X:1\nK:C")
        XCTAssertEqual(obj2["seed"] as? Int, 7)
        XCTAssertEqual(obj2["guidance"] as? Double, 1.2)
    }
}
