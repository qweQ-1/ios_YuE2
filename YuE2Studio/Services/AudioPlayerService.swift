import AVFoundation
import Foundation

/// 音频播放服务：stream 端点（m4a + Range），后台可播放（Info.plist 已开 audio 后台模式）。
public final class AudioPlayerService: NSObject, ObservableObject {
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    @Published public private(set) var isPlaying = false
    @Published public private(set) var currentTime: Double = 0
    @Published public private(set) var duration: Double = 0
    @Published public private(set) var failure: String?

    public override init() {
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }

    deinit {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
    }

    /// 载入并播放。headers 用于带 API Key 的服务器。
    public func play(url: URL, headers: [String: String]) {
        stopInternal()
        let options: [String: Any]? = headers.isEmpty
            ? nil
            : ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let item = AVPlayerItem(asset: AVURLAsset(url: url, options: options))
        let p = AVPlayer(playerItem: item)
        self.player = p

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                self?.isPlaying = false
            }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            guard let self else { return }
            self.currentTime = t.seconds.isFinite ? t.seconds : 0
            if let d = self.player?.currentItem?.duration.seconds, d.isFinite, d > 0 {
                self.duration = d
            }
            if self.player?.currentItem?.status == .failed {
                self.failure = "音频加载失败，请确认服务器可访问"
                self.isPlaying = false
            }
        }
        p.play()
        isPlaying = true
        failure = nil
    }

    public func toggle(url: URL, headers: [String: String]) {
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else if let player, player.currentItem != nil {
            player.play()
            isPlaying = true
        } else {
            play(url: url, headers: headers)
        }
    }

    public func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
    }

    public func stop() {
        stopInternal()
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    private func stopInternal() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        self.player?.pause()
        self.player = nil
    }
}
