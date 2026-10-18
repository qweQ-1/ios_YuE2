import Foundation

/// ABC 记谱法的最小解析：提取标题与段落标签，供列表展示与标题兜底。
public struct ABCParser {
    public private(set) var title: String
    public private(set) var sections: [String]
    public private(set) var isValid: Bool

    public init?(abc: String?) {
        guard let abc, !abc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let trimmed = abc.trimmingCharacters(in: .whitespacesAndNewlines)
        var title = ""
        var sections: [String] = []
        var isValid = false

        for rawLine in trimmed.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("X:") { isValid = true; continue }
            if line.hasPrefix("T:") && title.isEmpty {
                title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                continue
            }
            // 段落标签：行内任意位置的 [Verse] / [Chorus]（含 w:[Verse] 歌词行）
            var scan = line
            while let open = scan.firstIndex(of: "["),
                  let close = scan[open...].firstIndex(of: "]") {
                let tag = String(scan[scan.index(after: open)..<close])
                if !tag.isEmpty, !sections.contains(tag) { sections.append(tag) }
                scan = String(scan[scan.index(after: close)...])
            }
        }
        self.title = title
        self.sections = sections
        self.isValid = isValid
    }

    /// 列表显示的标题：优先 T:，否则首行，最后兜底「未命名乐谱」。
    public var displayTitle: String {
        if !title.isEmpty { return title }
        if let s = sections.first { return s }
        return "未命名乐谱"
    }

    /// 段落摘要，如「Verse · Chorus」。
    public var sectionSummary: String {
        sections.isEmpty ? "" : sections.joined(separator: " · ")
    }
}
