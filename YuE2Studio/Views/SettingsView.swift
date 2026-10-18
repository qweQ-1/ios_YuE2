import SwiftUI

/// 设置页：服务器信息、默认模式、本地历史、关于。
struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var history: HistoryStore
    @State private var health: ServerHealth?
    @State private var message: String?
    @State private var showSetup = false

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器") {
                    HStack {
                        Text("地址")
                        Spacer()
                        Text(settings.serverAddress.isEmpty ? "未设置" : settings.serverAddress)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !settings.apiKey.isEmpty {
                        HStack {
                            Text("API Key")
                            Spacer()
                            Text("已设置").foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        Task { await checkHealth() }
                    } label: {
                        HStack {
                            Text("连接状态")
                            Spacer()
                            if let health {
                                Text(health.summaryText).font(.caption).foregroundStyle(.secondary)
                            } else if let message {
                                Text(message).font(.caption).foregroundStyle(.orange)
                            } else {
                                Text("点击测试").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("修改服务器") { showSetup = true }
                }

                Section("创作") {
                    Picker("默认模式", selection: $settings.defaultCot) {
                        ForEach(CotMode.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section("本地历史（\(history.all().count) 条）") {
                    Button("清空本地历史", role: .destructive) { history.clear() }
                    Text("历史只保存在本机，音频文件以服务器为准。").font(.caption).foregroundStyle(.secondary)
                }

                Section("关于") {
                    Link("YuE2 开源项目（GitHub）", destination: URL(string: "https://github.com/multimodal-art-projection/YuE")!)
                    Link("YuE2 模型（Hugging Face）", destination: URL(string: "https://huggingface.co/m-a-p/YuE2-3B")!)
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    Text("YuE2 采用 Apache-2.0 许可证。本 App 是 YuE2 的非官方客户端，歌曲由你自建的服务器生成；模型运行需要 NVIDIA GPU，iPhone 本地无法推理。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .navigationTitle("设置")
            .sheet(isPresented: $showSetup) {
                ServerSetupView(mode: .missing)
            }
        }
    }

    private func checkHealth() async {
        message = nil
        do {
            health = try await environment.client().health()
        } catch let e as APIError {
            message = e.message
        } catch {
            message = error.localizedDescription
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppEnvironment(settings: SettingsStore(defaults: UserDefaults(suiteName: "preview-settings")!)))
        .environmentObject(SettingsStore(defaults: UserDefaults(suiteName: "preview-settings")!))
        .environmentObject(HistoryStore(directoryURL: FileManager.default.temporaryDirectory))
}
