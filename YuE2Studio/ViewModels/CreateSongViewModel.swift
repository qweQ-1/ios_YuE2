import Foundation

/// 创作表单 ViewModel。
@MainActor
public final class CreateSongViewModel: ObservableObject {
    @Published public var style: String = ""
    @Published public var lyrics: String = ""
    @Published public var cot: CotMode = .full
    @Published public var abc: String = ""
    @Published public var seedText: String = ""
    @Published public var guidanceText: String = ""
    @Published public var isSubmitting = false
    @Published public var errorMessage: String?
    /// 提交成功后回调（导航到任务详情）。
    public var onCreated: ((String) -> Void)?

    private let clientProvider: () -> YuE2Servicing
    private let history: HistoryStore

    public init(clientProvider: @escaping () -> YuE2Servicing, history: HistoryStore) {
        self.clientProvider = clientProvider
        self.history = history
    }

    private var service: YuE2Servicing { clientProvider() }

    // MARK: 表单校验

    public var trimmedStyle: String { style.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var trimmedLyrics: String { lyrics.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var trimmedABC: String { abc.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var canSubmit: Bool {
        !trimmedStyle.isEmpty && !trimmedLyrics.isEmpty && !isSubmitting
    }

    public var seedValue: Int? {
        let s = seedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : Int(s)
    }

    public var guidanceValue: Double? {
        let s = guidanceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let v = Double(s)
        return (v ?? 0) > 0 ? v : nil
    }

    /// 逐项校验，返回第一条错误信息；全部合法返回 nil。
    public func validationMessage() -> String? {
        if trimmedStyle.isEmpty { return "请填写风格提示（Style prompt）" }
        if trimmedLyrics.isEmpty { return "请填写歌词（Lyrics）" }
        if cot.acceptsABC && !trimmedABC.isEmpty && !trimmedABC.hasPrefix("X:") {
            return "ABC 乐谱需要以 X: 开头（YuE2 生成的乐谱可直接粘贴）"
        }
        if !seedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seedValue == nil {
            return "随机种子只能是整数"
        }
        if !guidanceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && guidanceValue == nil {
            return "Guidance 只能是大于 0 的数字"
        }
        return nil
    }

    /// 组装请求（当前表单状态）。
    public func makeRequest() -> GenerateRequest? {
        guard let msg = validationMessage() else {
            return GenerateRequest(style: trimmedStyle, lyrics: trimmedLyrics, cot: cot,
                                   abc: trimmedABC.isEmpty ? nil : trimmedABC,
                                   seed: seedValue, guidance: guidanceValue)
        }
        errorMessage = msg
        return nil
    }

    // MARK: 提交

    public func submit() {
        guard !isSubmitting, let request = makeRequest() else { return }
        errorMessage = nil
        isSubmitting = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isSubmitting = false }
            do {
                let jobId = try await self.service.generate(request)
                let entry = HistoryEntry(id: jobId, title: Formatters.shortTitle(from: request.style),
                                         style: request.style, cot: request.cot,
                                         createdAt: Date(), lastStatus: .queued)
                self.history.addOrUpdate(entry)
                self.onCreated?(jobId)
                self.resetForm()
            } catch let e as APIError {
                self.errorMessage = e.message
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    public func resetForm() {
        style = ""
        lyrics = ""
        abc = ""
        seedText = ""
        guidanceText = ""
    }

    /// 风格示例 chips。
    public static let styleExamples: [String] = [
        "Mandarin, city pop, warm female vocal, neon synths, saxophone solo, 100 BPM",
        "English, acoustic folk, male vocal, fingerstyle guitar, light strings, 88 BPM",
        "Japanese, rock ballad, powerful vocal, distorted guitars, driving drums, 140 BPM",
        "Instrumental, lo-fi hip hop, dusty piano, vinyl crackle, swung drums, 75 BPM"
    ]
}
