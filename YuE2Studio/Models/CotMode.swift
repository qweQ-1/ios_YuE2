import Foundation

/// cot 模式对应 YuE2 的三种创作方式（前端选项文案对齐官方 README）。
public enum CotMode: String, Codable, CaseIterable, Identifiable {
    case full
    case melody
    case off

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .full: return "完整规划"
        case .melody: return "仅旋律"
        case .off: return "直接生成"
        }
    }

    public var subtitle: String {
        switch self {
        case .full: return "生成带和弦的乐谱后再编曲，可编辑、最稳"
        case .melody: return "只规划主旋律，伴奏自由发挥，适合翻唱"
        case .off: return "跳过乐谱直接出歌，最快但不透明"
        }
    }

    /// 是否接受用户自带 ABC 乐谱。
    public var acceptsABC: Bool { self != .off }
}
