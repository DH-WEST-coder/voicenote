import AVFoundation
import Foundation

@MainActor
final class AudioPlayer: ObservableObject {
    static let shared = AudioPlayer()
    @Published var currentTime: Double = 0
    @Published var isPlaying = false
    @Published var loadedPath: String?
    @Published var error: String?
    private var player: AVAudioPlayer?
    private var timer: Timer?

    var duration: Double { player?.duration ?? 0 }

    func play(path: String, from t: Double? = nil) {
        if loadedPath != path || player == nil {
            stop()
            do {
                player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
                loadedPath = path
                error = nil
            } catch {
                self.error = "오디오 파일을 열 수 없습니다: \((path as NSString).lastPathComponent)"
                return
            }
        }
        if let t { player?.currentTime = max(0, t); currentTime = max(0, t) }
        player?.play()
        isPlaying = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let p = self.player else { return }
                self.currentTime = p.currentTime
                self.isPlaying = p.isPlaying
                if !p.isPlaying { self.timer?.invalidate() }
            }
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
    }

    func stop() {
        player?.stop()
        player = nil
        loadedPath = nil
        isPlaying = false
        currentTime = 0
        timer?.invalidate()
    }
}
