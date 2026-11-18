import AVFoundation
import MediaPlayer

/// One shared video player for the iPhone screen and CarPlay.
/// AirPlay is switched on, so the video can go to a car screen that supports
/// CarPlay video (parked only). If the car doesn't allow video, you still hear the sound.
final class VideoPlayerManager: ObservableObject {
    static let shared = VideoPlayerManager()

    let player = AVPlayer()
    @Published private(set) var current: VideoFile?
    @Published private(set) var isPlaying = false

    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback,
                                                         mode: .moviePlayback,
                                                         policy: .longFormVideo,
                                                         options: [])
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true

        setupRemoteCommands()

        // Keep the CarPlay progress bar up to date.
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 1),
                                                      queue: .main) { [weak self] _ in
            self?.updateNowPlaying()
        }

        // Notice play / pause from the iPhone's built-in video controls too.
        statusObserver = player.observe(\.timeControlStatus) { [weak self] player, _ in
            DispatchQueue.main.async {
                self?.isPlaying = player.timeControlStatus != .paused
                self?.updateNowPlaying()
            }
        }
    }

    func play(_ video: VideoFile) {
        try? AVAudioSession.sharedInstance().setActive(true)
        player.replaceCurrentItem(with: AVPlayerItem(url: video.url))
        player.play()
        current = video
        updateNowPlaying()
    }

    func resume() {
        guard current != nil else { return }
        if let item = player.currentItem, item.currentTime() >= item.duration {
            player.seek(to: .zero)
        }
        player.play()
    }

    func pause() { player.pause() }

    func toggle() { isPlaying ? pause() : resume() }

    func skip(by seconds: Double) {
        let target = player.currentTime().seconds + seconds
        player.seek(to: CMTime(seconds: max(0, target), preferredTimescale: 600))
        updateNowPlaying()
    }

    // Buttons on the CarPlay screen, steering wheel and lock screen.
    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        center.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }

        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in self?.skip(by: 15); return .success }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in self?.skip(by: -15); return .success }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.player.seek(to: CMTime(seconds: event.positionTime, preferredTimescale: 600))
            return .success
        }
    }

    // Title, time and progress shown on CarPlay's Now Playing screen.
    private func updateNowPlaying() {
        guard let video = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: video.name,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime().seconds,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let duration = player.currentItem?.duration.seconds, duration.isFinite {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
