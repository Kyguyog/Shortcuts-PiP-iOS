import AVFoundation
import AVKit
import UIKit
import Combine

/// Owns the AVPictureInPictureController and coordinates with SampleBufferSource.
/// Shared singleton so App Intents (which run in-process on iOS 16+) can reach it.
@MainActor
final class PiPManager: NSObject, ObservableObject {

    static let shared = PiPManager()

    // MARK: - Public state

    @Published private(set) var isPiPActive = false
    @Published private(set) var currentText: String = "Ready"

    // MARK: - Internal

    private let bufferSource = SampleBufferSource()
    var displayLayer: AVSampleBufferDisplayLayer { bufferSource.displayLayer }

    private var pipController: AVPictureInPictureController?
    weak var attachedView: UIView?

    private var darwinCancellables = [Any]()

    // MARK: - Init

    private override init() {
        super.init()
        configureAudioSession()
        buildPiPController()
        listenForDarwinNotifications()
    }

    // MARK: - Public API (called by UI + App Intents)

    func setText(_ text: String) {
        currentText = text
        bufferSource.text = text
    }

    func startPiP() {
        bufferSource.start()

        guard let pip = pipController else {
            buildPiPController()
            pipController?.startPictureInPicture()
            return
        }

        if AVPictureInPictureController.isPictureInPictureSupported() {
            pip.startPictureInPicture()
        }
    }

    func stopPiP() {
        pipController?.stopPictureInPicture()
        bufferSource.stop()
    }

    // MARK: - Setup

    private func configureAudioSession() {
        // PiP on iOS requires an active audio session, even if you play silence.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[PiPManager] Audio session error: \(error)")
        }
    }

    private func buildPiPController() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("[PiPManager] PiP not supported on this device/iOS version.")
            return
        }

        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        let pip = AVPictureInPictureController(contentSource: contentSource)
        pip.delegate = self
        // Allow PiP to start automatically when the app goes to background.
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        pipController = pip
    }

    // MARK: - Darwin cross-process wakeup

    private func listenForDarwinNotifications() {
        DarwinNotifier.observe(.textDidChange) { [weak self] in
            guard let self else { return }
            let text = UserDefaults(suiteName: AppGroup.id)?.string(forKey: AppGroup.textKey) ?? ""
            self.setText(text)
        }
        DarwinNotifier.observe(.startPiP) { [weak self] in self?.startPiP() }
        DarwinNotifier.observe(.stopPiP)  { [weak self] in self?.stopPiP() }
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension PiPManager: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in self.isPiPActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in self.isPiPActive = false }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        print("[PiPManager] Failed to start PiP: \(error)")
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension PiPManager: AVPictureInPictureSampleBufferPlaybackDelegate {

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        // No-op: our frame pump runs independently.
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        // Return a very long finite range so iOS doesn't think we're at the end.
        return CMTimeRange(start: .zero, duration: CMTime(value: 86400, timescale: 1))
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        return false
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {
        // Could adjust resolution here if needed.
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
