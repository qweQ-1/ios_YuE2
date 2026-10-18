import Foundation

/// 服务器地址规范化与校验。
public enum ServerURL {
    /// 用户输入 → 规范 base URL。
    /// - 自动补 https://（未写 scheme 时）
    /// - 去掉末尾 `/` 与空白
    /// - 校验 host 存在
    /// - 返回 nil 表示无法作为合法地址
    public static func normalize(_ input: String) -> URL? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") {
            // http:// 常见于局域网自建；无端口时优先 https，其余统一 https。
            s = "https://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s),
              let scheme = url.scheme, scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// 简单可用性提示文案（供 UI 报错）。
    public static func validationMessage(_ input: String) -> String? {
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请先填写服务器地址"
        }
        if normalize(input) == nil {
            return "地址格式不正确，例如 https://yue2.example.com"
        }
        return nil
    }
}
