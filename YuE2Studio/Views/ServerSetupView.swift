import SwiftUI

/// 首次引导 / 服务器地址缺失时的设置页。
struct ServerSetupView: View {
    enum Mode {
        case onboarding   // 首次启动，直接全屏
        case missing      // 地址被清空后从设置进入
    }

    var mode: Mode
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @State private var address: String = ""
    @State private var apiKey: String = ""
    @State private var health: ServerHealth?
    @State private var message: String?
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    SectionCard(title: "服务器") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("地址")
                                .font(.caption).foregroundStyle(.secondary)
                            TextField("https://yue2.example.com", text: $address)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(10)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            if let msg = ServerURL.validationMessage(address) {
                                Text(msg).font(.caption).foregroundStyle(.orange)
                            }

                            Text("API Key（服务器未设置可留空）")
                                .font(.caption).foregroundStyle(.secondary)
                            SecureField("X-API-Key", text: $apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(10)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    SectionCard(title: "连接测试") {
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                Task { await test() }
                            } label: {
                                HStack {
                                    if isTesting { ProgressView().scaleEffect(0.8) }
                                    Text(isTesting ? "测试中…" : "测试连接")
                                }
                            }
                            .disabled(ServerURL.normalize(address) == nil || isTesting)

                            if let health {
                                Label(health.summaryText, systemImage: health.engine == .ready ? "checkmark.circle.fill" : "info.circle.fill")
                                    .font(.callout)
                                    .foregroundStyle(health.engine == .error ? .orange : .green)
                                if health.stub {
                                    Text("当前是 Stub 演示服务器：不会真的调用 GPU 模型，仅用于联调界面。")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if let message {
                                Text(message).font(.callout).foregroundStyle(.red)
                            }
                            Text("需要一台带 NVIDIA GPU（BF16、≥24GB 显存）的 Linux 机器运行 YuE2 服务端；部署方法见仓库 server/README.md。")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }

                    PrimaryButton("保存并开始", systemImage: "checkmark",
                                  isEnabled: ServerURL.normalize(address) != nil) {
                        save()
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(mode == .onboarding ? "连接 YuE2 服务器" : "服务器设置")
        }
        .onAppear {
            address = settings.serverAddress
            apiKey = settings.apiKey
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accentGradient)
            Text("YuE2 Studio")
                .font(.title.weight(.bold))
            Text("输入歌词与风格，让 YuE2 生成完整歌曲\n（带可查看的乐谱）")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func test() async {
        guard let url = ServerURL.normalize(address) else { return }
        isTesting = true
        message = nil
        health = nil
        defer { isTesting = false }
        do {
            let c = YuE2Client(baseURL: url, apiKey: apiKey)
            health = try await c.health()
        } catch let e as APIError {
            message = e.message
        } catch {
            message = error.localizedDescription
        }
    }

    private func save() {
        settings.serverAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.onboardingDone = true
    }
}

#Preview {
    ServerSetupView(mode: .onboarding)
        .environmentObject(AppEnvironment(settings: SettingsStore(defaults: UserDefaults(suiteName: "preview-setup")!)))
        .environmentObject(SettingsStore(defaults: UserDefaults(suiteName: "preview-setup")!))
}
