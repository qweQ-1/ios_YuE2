import SwiftUI

/// 播放条：播放/暂停 + 进度 + 时间。播放服务由外部注入（全局环境持有）。
struct PlayerBar: View {
    let url: URL
    let headers: [String: String]
    @ObservedObject var service: AudioPlayerService

    init(url: URL, headers: [String: String], service: AudioPlayerService) {
        self.url = url
        self.headers = headers
        self.service = service
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Button {
                    service.toggle(url: url, headers: headers)
                } label: {
                    Image(systemName: service.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.accentGradient)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(Formatters.duration(service.currentTime))
                        .font(.caption).monospacedDigit()
                    Slider(value: Binding(get: { service.currentTime },
                                          set: { service.seek(to: $0) }),
                           in: 0...max(service.duration, 0.1))
                    .disabled(service.duration <= 0)
                    Text("-\(Formatters.duration(max(service.duration - service.currentTime, 0)))")
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Button {
                    service.stop()
                } label: {
                    Image(systemName: "stop.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            if let failure = service.failure {
                Text(failure).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

#Preview {
    PlayerBar(url: URL(string: "https://example.com/a.m4a")!, headers: [:],
              service: AudioPlayerService())
        .padding()
}
