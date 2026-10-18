import Foundation

/// JSON 样例构造器，VM 测试共享。
enum Fixtures {
    static func detail(id: String = "job-1", status: JobStatus = .running,
                       phase: JobPhase = .planning) -> JobDetail {
        let json: [String: Any] = [
            "id": id,
            "status": status.rawValue,
            "created_at": "2026-10-18T07:30:00Z",
            "updated_at": "2026-10-18T07:35:12Z",
            "progress": ["phase": phase.rawValue, "message": "规划乐谱 · 12", "tokens": 12],
            "error": NSNull(),
            "result": NSNull(),
            "urls": [
                "audio": "/api/jobs/\(id)/audio",
                "stream": "/api/jobs/\(id)/stream",
                "score": "/api/jobs/\(id)/score.abc",
            ],
            "params": [
                "style": "English, warm piano pop",
                "lyrics": "[Verse]\nline one",
                "cot": "full",
                "abc": NSNull(),
                "seed": 42,
                "guidance": NSNull(),
            ],
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder.yue2.decode(JobDetail.self, from: data)
    }

    static func doneDetail(id: String = "job-1") -> JobDetail {
        var d = detail(id: id, status: .succeeded, phase: .done)
        d.progress = JobProgress(phase: .done, message: "")
        d.error = nil
        let json: [String: Any] = [
            "audio_seconds": 182.4,
            "sample_rate": 48000,
            "truncated": ["abc": false, "semantic": true],
            "timing": ["abc_seconds": 20.1, "semantic_seconds": 90.2, "nar_seconds": 120.5, "vae_seconds": 40.2, "e2e_seconds": 271.0],
            "identity": "sha256:deadbeef",
        ]
        d.result = try! JSONDecoder().decode(JobResult.self, from: try! JSONSerialization.data(withJSONObject: json))
        return d
    }

    static func summary(id: String = "job-1", status: JobStatus = .succeeded) -> JobSummary {
        JobSummary(id: id, status: status, createdAt: "2026-10-18T07:30:00Z",
                   style: "English, warm piano pop, female vocal", lyricsExcerpt: "[Verse] Neon…",
                   cot: .full, audioSeconds: 182.4, seed: 831001)
    }
}
