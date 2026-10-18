import SwiftUI

/// 全站配色：深夜录音棚风，紫青渐变作主色。
enum Theme {
    static let accent = Color(red: 0.55, green: 0.36, blue: 0.96)      // 紫
    static let accent2 = Color(red: 0.20, green: 0.78, blue: 0.90)     // 青
    static let background = Color(red: 0.06, green: 0.06, blue: 0.10)
    static let card = Color(red: 0.11, green: 0.11, blue: 0.17)
    static let cardBorder = Color.white.opacity(0.08)

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // 状态色
    static func color(for phase: String) -> Color {
        switch phase {
        case "queued": return .orange
        case "planning": return .purple
        case "semantic": return .indigo
        case "synthesizing": return .teal
        case "decoding": return .mint
        case "done": return .green
        default: return .secondary
        }
    }
}

/// 圆角卡片容器，统一全 App 的区块观感。
struct SectionCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }
}

/// 渐变主按钮。
struct PrimaryButton: View {
    var title: String
    var systemImage: String?
    var isEnabled: Bool = true
    var action: () -> Void

    init(_ title: String, systemImage: String? = nil, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
        }
        .disabled(!isEnabled)
    }
}

/// 小号胶囊（用于 cot 模式、状态等）。
struct Pill: View {
    var text: String
    var color: Color = Theme.accent
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(filled ? color : color.opacity(0.16), in: Capsule())
            .foregroundStyle(filled ? .white : color)
    }
}

/// 多行文本编辑器 + 占位提示。
struct PlaceholderTextEditor: View {
    var placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 120

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
            }
            TextEditor(text: $text)
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
                .padding(4)
        }
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
