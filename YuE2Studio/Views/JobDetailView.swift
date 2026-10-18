import SwiftUI
import UIKit

/// 任务详情：进度、播放、乐谱、参数复用。
struct JobDetailView: View {
    @ObservedObject var vm: JobDetailViewModel
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showScore = false
    @State private var shareURL: URL?
    @State private var downloadMessage: String?
    @State private var isDownloading = false
    @State private var showRetry = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusCard
                if let error = vm.errorMessage {
                    SectionCard(title: "提示") {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
                if vm.detail?.status == .succeeded, vm.detail?.result != nil {
                    playerCard
                    resultCard
                    actionsCard
                }
                paramsCard
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("任务详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await vm.load()
            vm.startPolling()
        }
        .onDisappear { vm.stopPolling() }
        .sheet(isPresented: $shareURL.isNotNil()) {
            if let shareURL {
                ShareSheet(items: [shareURL])
            }
        }
        .alert("下载失败", isPresented: .constant(downloadMessage != nil)) {
            Button("好") { downloadMessage = nil }
        } message: {
            Text(downloadMessage ?? "")
        }
        .sheet(isPresented: $showRetry) {
            if let request = vm.makeRetryRequest() {
                RetrySheet(request: request) { env in
                    let vm2 = env.createSongViewModel
                    vm2.style = request.style
                    vm2.lyrics = request.lyrics
                    vm2.cot = request.cot
                    vm2.abc = request.abc ?? ""
                    vm2.seedText = request.seed.map(String.init) ?? ""
                    vm2.guidanceText = request.guidance.map { String(format: "%.2f", $0) } ?? ""
                    showRetry = false
                }
            }
        }
    }

    // MARK: 卡片

    private var statusCard: some View {
        SectionCard(title: "状态") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if let d = vm.detail {
                        Pill(text: d.status.label, color: statusColor, filled: true)
                        Spacer()
                        Text(Formatters.displayDate(d.createdAt))
                            .font(.caption).foregroundStyle(.secondary)
                    } else if vm.isLoading {
                        HStack { ProgressView().scaleEffect(0.8); Text("加载中…").foregroundStyle(.secondary) }
                    }
                }
                if let d = vm.detail, d.status.isActive {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.9)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.progress.phase.label).font(.callout.weight(.medium))
                            if !d.progress.message.isEmpty {
                                Text(d.progress.message).font(.caption).foregroundStyle(.secondary)
                            }
                            if let tokens = d.progress.tokens {
                                Text("\(tokens.formatted()) tokens").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Button("取消", role: .destructive) { vm.cancelJob() }
                            .buttonStyle(.bordered)
                    }
                    if let f = d.progress.fraction {
                        ProgressView(value: f)
                    } else {
                        ProgressView().padding(.top, 4)
                    }
                }
                if let d = vm.detail, d.status == .failed, let err = d.error {
                    Text(err).font(.callout).foregroundStyle(.red)
                }
            }
        }
    }

    private var playerCard: some View {
        SectionCard(title: "试听") {
            PlayerBar(url: environment.client().streamURL(id: vm.jobId),
                      headers: environment.client().authHeaders(),
                      service: environment.player)
        }
    }

    private var resultCard: some View {
        SectionCard(title: "作品信息") {
            VStack(alignment: .leading, spacing: 6) {
                if let r = vm.detail?.result {
                    infoRow("时长", Formatters.duration(r.audioSeconds))
                    infoRow("采样率", "\(r.sampleRate) Hz")
                    if r.truncatedAbc || r.truncatedSemantic {
                        infoRow("提示", "本次生成被截断（\(r.truncatedAbc ? "乐谱" : "")\(r.truncatedAbc && r.truncatedSemantic ? " + " : "")\(r.truncatedSemantic ? "旋律" : "")），可能需要缩短歌词")
                            .foregroundStyle(.orange)
                    }
                    if let e2e = r.timing?.e2eSeconds {
                        infoRow("耗时", String(format: "%.0f 秒", e2e))
                    }
                }
            }
        }
    }

    private var actionsCard: some View {
        SectionCard(title: "操作") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        Task { await downloadAndShare() }
                    } label: {
                        Label(isDownloading ? "下载中…" : "保存音频", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isDownloading)
                    Button("查看乐谱", systemImage: showScore ? "chevron.up" : "music.quarternote.3") {
                        showScore.toggle()
                    }
                    .buttonStyle(.bordered)
                }
                HStack(spacing: 10) {
                    Button("复制乐谱文本", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = vm.score ?? ""
                    }
                    .buttonStyle(.bordered)
                    Button("重新创作", systemImage: "arrow.clockwise") {
                        showRetry = true
                    }
                    .buttonStyle(.bordered)
                }
                if showScore {
                    ScoreWebView(abc: vm.score ?? "（乐谱不存在）")
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var paramsCard: some View {
        SectionCard(title: "创作参数") {
            VStack(alignment: .leading, spacing: 6) {
                if let d = vm.detail {
                    infoRow("模式", (d.paramsCot ?? .full).title)
                    if let style = d.paramsStyle { infoRow("风格", style) }
                    if let lyrics = d.paramsLyrics {
                        Text(lyrics)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(8)
                    }
                    if let seed = d.paramsSeed { infoRow("种子", String(seed)) }
                    if let abc = d.paramsAbc, !abc.isEmpty {
                        Text(abc)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(6)
                    }
                }
            }
        }
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }

    private var statusColor: Color {
        switch vm.detail?.status {
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled: return .gray
        case .running, .queued, .none: return .purple
        }
    }

    private func downloadAndShare() async {
        guard let client = Optional(environment.client()) else { return }
        isDownloading = true
        defer { isDownloading = false }
        do {
            let local = try await FileExporter.download(
                from: client.audioURL(id: vm.jobId),
                headers: client.authHeaders(),
                suggestedName: "YuE2-\(String(vm.jobId.prefix(8))).flac")
            shareURL = local
        } catch let e as APIError {
            downloadMessage = e.message
        } catch {
            downloadMessage = error.localizedDescription
        }
    }
}

extension Binding where Value == URL? {
    /// sheet(isPresented:) 需要 Bool，这里借「URL 是否有值」驱动。
    fileprivate var isNotNil: Binding<Bool> {
        Binding(get: { wrappedValue != nil }, set: { if !$0 { wrappedValue = nil } })
    }
}

/// 系统分享面板。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// 重新创作确认面板（预填参数）。
struct RetrySheet: View {
    let request: GenerateRequest
    let onConfirm: (AppEnvironment) -> Void
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("将用同样的参数在「创作」页重新提交：").font(.headline)
                Text(request.style).font(.callout).foregroundStyle(.secondary)
                Text("歌词 \(request.lyrics.count) 字 · 模式 \(request.cot.title)")
                    .font(.caption).foregroundStyle(.secondary)
                Text("点击后参数会预填到创作页，切换到「创作」标签提交即可。")
                    .font(.caption).foregroundStyle(.tertiary)
                PrimaryButton("去创作页") {
                    onConfirm(environment)
                }
            }
            .padding(20)
            .navigationTitle("重新创作")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    JobDetailView(vm: {
        let vm = JobDetailViewModel(jobId: "20261018-abcdef", clientProvider: { DeadClient() },
                                    history: HistoryStore(directoryURL: FileManager.default.temporaryDirectory))
        return vm
    }())
    .environmentObject(AppEnvironment(settings: SettingsStore(defaults: UserDefaults(suiteName: "preview-detail")!)))
}
