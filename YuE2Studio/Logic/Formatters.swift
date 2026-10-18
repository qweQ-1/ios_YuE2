import Foundation

/// 展示层小工具：时长、日期、标题兜底。
public enum Formatters {
    /// 182.4 → "3:02"
    public static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// ISO8601 → "10-18 15:30"，解析失败原样返回。
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public static func displayDate(_ isoString: String) -> String {
        guard let date = iso.date(from: isoString) else { return isoString }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }

    /// style 文本兜底为短标题（列表行首）。
    public static func shortTitle(from style: String, limit: Int = 40) -> String {
        let s = style.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "未填写风格" }
        return s.count <= limit ? s : String(s.prefix(limit)) + "…"
    }
}
