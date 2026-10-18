import SwiftUI

/// 创作页：风格 + 歌词 + 创作模式 + 可选乐谱 + 种子。
struct CreateSongView: View {
    @ObservedObject var vm: CreateSongViewModel
    @State private var showAdvanced = false
    @State private var showABC = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            form
                .navigationDestination(for: String.self) { jobId in
                    JobDetailView(vm: JobDetailShell.vm(jobId: jobId))
                }
        }
        .onAppear { vm.onCreated = { path.append($0) } }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionCard(title: "风格提示（Style prompt）") {
                    VStack(alignment: .leading, spacing: 10) {
                        PlaceholderTextEditor(
                            placeholder: "例：Mandarin, city pop, warm female vocal, neon synths, saxophone solo, 100 BPM",
                            text: $vm.style, minHeight: 70)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(CreateSongViewModel.styleExamples, id: \.self) { preset in
                                    Button(preset) { vm.style = preset }
                                        .font(.caption)
                                        .lineLimit(1)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Theme.accent.opacity(0.16), in: Capsule())
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                }

                SectionCard(title: "歌词（Lyrics）") {
                    VStack(alignment: .leading, spacing: 8) {
                        PlaceholderTextEditor(
                            placeholder: "[Verse]\n……\n\n[Chorus]\n……",
                            text: $vm.lyrics, minHeight: 180)
                        Text("\(vm.lyrics.count) 字 · 支持 [Verse] / [Chorus] / [Bridge] 等段落标记")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }

                SectionCard(title: "创作模式") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("cot", selection: $vm.cot) {
                            ForEach(CotMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(vm.cot.subtitle).font(.caption).foregroundStyle(.secondary)

                        if vm.cot.acceptsABC {
                            Disclosure(isExpanded: $showABC) {
                                VStack(alignment: .leading, spacing: 8) {
                                    PlaceholderTextEditor(
                                        placeholder: "可选：粘贴 ABC 乐谱（以 X: 开头）。YuE2 首次生成的乐谱可在任务详情页复制。",
                                        text: $vm.abc, minHeight: 120)
                                    Text("提供乐谱后将按谱编曲，适合二次编辑后重渲染。").font(.caption2).foregroundStyle(.tertiary)
                                }
                            } label: {
                                Label(showABC ? "收起乐谱输入" : "使用已有 ABC 乐谱（可选）",
                                      systemImage: showABC ? "chevron.up" : "chevron.down")
                            }
                        }
                    }
                }

                SectionCard(title: "高级") {
                    Disclosure(isExpanded: $showAdvanced) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("随机种子")
                                Spacer()
                                TextField("留空 = 随机", text: $vm.seedText)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 140)
                            }
                            HStack {
                                Text("Guidance")
                                Spacer()
                                TextField("留空 = 默认", text: $vm.guidanceText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 140)
                            }
                            Text("种子相同则本次创作可复现；Guidance 控制提示遵循强度。").font(.caption2).foregroundStyle(.tertiary)
                        }
                    } label: {
                        Label(showAdvanced ? "收起高级选项" : "高级选项（种子 / Guidance）",
                              systemImage: showAdvanced ? "chevron.up" : "chevron.down")
                    }
                }

                if let error = vm.errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                PrimaryButton(vm.isSubmitting ? "提交中…" : "开始创作", systemImage: "sparkles",
                              isEnabled: vm.canSubmit) { vm.submit() }

                Text("生成一首完整歌曲通常需要几分钟，取决于服务器 GPU。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("创作")
    }
}

/// 折叠面板（目标 iOS 17 可直接用系统 Disclosure，这里保留自绘以控制字号与颜色）。
private struct Disclosure<Label: View, Content: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder var label: Label
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            label.font(.callout).foregroundStyle(Theme.accent)
            if isExpanded { content }
        }
    }
}

/// 任务详情 VM 的创建入口（App 启动时装配）。
/// 说明：导航目标由 CreateSongView 持有 path 后创建，VM 经全局环境取。
enum JobDetailShell {
    @MainActor static func vm(jobId: String) -> JobDetailViewModel {
        let env = AppEnvironmentHolder.shared
        return env.makeJobDetailViewModel(jobId: jobId)
    }
}

/// 共享的全局 AppEnvironment（App 入口注入，导航代码取用）。
final class AppEnvironmentHolder {
    static let shared: AppEnvironment = AppEnvironment()
}

#Preview {
    CreateSongView(vm: CreateSongViewModel(
        clientProvider: { DeadClient() },
        history: HistoryStore(directoryURL: FileManager.default.temporaryDirectory)))
}
