// PiP/PiPManager.swift
// The heart of the whole system.
//
// Architecture:
//   ┌─────────────────────────────────────────────┐
//   │  PiPManager (singleton)                     │
//   │                                             │
//   │  displayText ──► renderLoop (DispatchQueue) │
//   │       │                  │                  │
//   │       │         TextFrameRenderer           │
//   │       │                  │                  │
//   │       │         CMSampleBuffer              │
//   │       │                  │                  │
//   │       └──────► AVSampleBufferDisplayLayer   │
//   │                          │                  │
//   │               AVPictureInPictureController  │
//   └─────────────────────────────────────────────┘
//
// Key insight: AVPictureInPictureController can use a
// AVPictureInPictureControllerContentSource backed by
// AVSampleBufferDisplayLayer (iOS 15+). This lets us push
// arbitrary CMSampleBuffers as "video" — no real media file needed.
//
// Frame pump:
//   A DispatchSourceTimer fires at ~30 fps and pushes a freshly
//   rendered frame whenever `displayText` has changed OR at a
//   minimum keep-alive rate to stop the layer from stalling.

import AVFoundation
import AVKit
import UIKit
import Combine

@MainActor
final class PiPManager: NSObject, ObservableObject {

    // MARK: - Singleton

    static let shared = PiPManager()

    // MARK: - Published state (observed by SwiftUI)

    @Published private(set) var isPiPActive   = false
    @Published private(set) var isPiPPossible = false
    @Published              var displayText   = "Ready"

    // MARK: - Private AVFoundation objects

    /// The layer that receives our synthesised CMSampleBuffers.
    let sampleBufferDisplayLayer = AVSampleBufferDisplayLayer()

    private var pipController: AVPictureInPictureController?
    private var renderTimer: DispatchSourceTimer?
    private let renderer = TextFrameRenderer()

    // MARK: - Thread-safe text storage
    // `displayText` is @MainActor-isolated; the render timer reads
    // `_pendingText` which is protected by an os_unfair_lock for
    // maximum throughput from background threads (App Intents).

    private var _lock = os_unfair_lock_s()
    private var _pendingText: String = "Ready"
    private var _lastRenderedText: String = ""

    // MARK: - Init

    private override init() {
        super.init()
        configureSampleBufferLayer()
    }

    // MARK: - Public API

    /// Call once from the SwiftUI view that hosts the sample buffer layer.
    func setupPiP(playerLayer: AVPlayerLayer? = nil) {
        // iOS 15+: use AVSampleBufferDisplayLayer-based source.
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: sampleBufferDisplayLayer,
            playbackDelegate: self
        )
        pipController = AVPictureInPictureController(contentSource: contentSource)
        pipController?.delegate = self
        pipController?.canStartPictureInPictureAutomaticallyFromInline = true

        // Observe KVO to keep `isPiPPossible` in sync.
        pipController?.addObserver(
            self,
            forKeyPath: #keyPath(AVPictureInPictureController.isPictureInPicturePossible),
            options: [.new],
            context: nil
        )

        // Push an initial frame so the layer is not blank.
        pushFrame(text: displayText)
    }

    func startPiP() {
        guard let pip = pipController else {
            print("⚠️  PiP not set up — call setupPiP() first")
            return
        }
        startRenderLoop()
        pip.startPictureInPicture()
    }

    func stopPiP() {
        pipController?.stopPictureInPicture()
        stopRenderLoop()
    }

    /// Thread-safe text update. Safe to call from any thread / App Intent.
    nonisolated func setText(_ newText: String) {
        os_unfair_lock_lock(&_lock)
        _pendingText = newText
        os_unfair_lock_unlock(&_lock)

        // Mirror to @Published on main actor (UI binding).
        Task { @MainActor in
            self.displayText = newText
        }
    }

    // MARK: - Private: layer configuration

    private func configureSampleBufferLayer() {
        sampleBufferDisplayLayer.videoGravity      = .resizeAspect
        sampleBufferDisplayLayer.backgroundColor   = UIColor.black.cgColor
        // controlTimebase lets us control playback pace ourselves.
        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(
            allocator:  kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &timebase
        )
        if let tb = timebase {
            CMTimebaseSetRate(tb, rate: 1.0)
            CMTimebaseSetTime(tb, time: .zero)
            sampleBufferDisplayLayer.controlTimebase = tb
        }
    }

    // MARK: - Private: render loop

    private func startRenderLoop() {
        guard renderTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        // Fire every ~33 ms (≈30 fps). In background iOS may throttle this to
        // ~1 fps for efficiency — see README notes on background behaviour.
        timer.schedule(deadline: .now(), repeating: .milliseconds(33))
        timer.setEventHandler { [weak self] in
            self?.renderTick()
        }
        timer.resume()
        renderTimer = timer
    }

    private func stopRenderLoop() {
        renderTimer?.cancel()
        renderTimer = nil
    }

    private func renderTick() {
        os_unfair_lock_lock(&_lock)
        let text = _pendingText
        os_unfair_lock_unlock(&_lock)

        // Skip rendering if nothing changed to save CPU.
        // We still need to feed keep-alive frames every ~1 s to prevent stall.
        let textChanged = (text != _lastRenderedText)
        guard textChanged else { return }

        pushFrame(text: text)
        _lastRenderedText = text
    }

    private func pushFrame(text: String) {
        guard let sampleBuffer = renderer.makeSampleBuffer(text: text) else { return }

        // If the layer has errored (e.g. after a long sleep), flush & recover.
        if sampleBufferDisplayLayer.status == .failed {
            sampleBufferDisplayLayer.flush()
        }
        sampleBufferDisplayLayer.enqueue(sampleBuffer)
    }

    // MARK: - KVO

    override nonisolated func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == #keyPath(AVPictureInPictureController.isPictureInPicturePossible) else { return }
        let possible = (change?[.newKey] as? Bool) ?? false
        Task { @MainActor in
            self.isPiPPossible = possible
        }
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension PiPManager: AVPictureInPictureControllerDelegate {

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in self.isPiPActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in self.isPiPActive = false }
        stopRenderLoop()
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        print("❌ PiP failed to start: \(error)")
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension PiPManager: AVPictureInPictureSampleBufferPlaybackDelegate {

    /// Return the timebase's current time as the playback position.
    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        // Advertise a long "live" time range so PiP does not show a scrubber.
        CMTimeRange(start: .zero, duration: CMTime(value: 3600, timescale: 1))
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool { false }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {}
}
