import Foundation

/// FLAC 文件下载 + 系统分享（存到"文件" App / AirDrop / 其他 App）。
public enum FileExporter {
    /// 下载到临时目录，返回本地文件 URL。任何错误转成 APIError。
    public static func download(from remote: URL, headers: [String: String],
                                suggestedName: String) async throws -> URL {
        var req = URLRequest(url: remote, cachePolicy: .reloadIgnoringLocalCacheData)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        do {
            let (tmp, resp) = try await URLSession.shared.download(for: req)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw APIError.http(status: http.statusCode, message: "")
            }
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedName)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            return dest
        } catch let e as APIError {
            throw e
        } catch let e as URLError {
            throw APIError.network(e.yue2Reason)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }
}
