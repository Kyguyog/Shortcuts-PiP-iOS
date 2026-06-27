import AVFoundation
import Combine

/// Drives the AVSampleBufferDisplayLayer by pushing rendered frames on a
/// dedicated background queue at ~30 fps. When the displayed text changes,
/// the next pushed frame picks up the new content automatically.
final class SampleBufferSource {

    // The layer that PiP reads from.
    let displayLayer = AVSampleBufferDisplayLayer()

    private let renderQueue = DispatchQueue(label: "pip.render", qos: .userInteractive)
    private var displayLink: CADisplayLink?
    private var frameCount: Int64 = 0
    private var isRunning = false

    // Thread-safe text storage — written from main thread, read from render queue.
    private let textLock = NSLock()
    private var _text: String = "Ready"
    var text: String {
        get { textLock.lock(); defer { textLock.unlock() }; return _text }
        set { textLock.lock(); _text = newValue; textLock.unlock() }
    }

    init() {
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Prime the layer with the first frame immediately so PiP has something
        // to show before the repeating timer fires.
        pushFrame()

        // Use a CADisplayLink on the render queue for smooth 30 fps delivery.
        // CADisplayLink must be added to a RunLoop — we spin one on our queue.
        renderQueue.async { [weak self] in
            guard let self else { return }
            let link = CADisplayLink(target: self, selector: #selector(self.tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
            link.add(to: .current, forMode: .common)
            self.displayLink = link
            RunLoop.current.run() // keeps the thread alive while the link fires
        }
    }

    func stop() {
        isRunning = false
        renderQueue.async { [weak self] in
            self?.displayLink?.invalidate()
            self?.displayLink = nil
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        displayLayer.flushAndRemoveImage()
    }

    // MARK: - Frame push

    @objc private func tick() {
        pushFrame()
    }

    private func pushFrame() {
        let currentText = text
        guard let pixelBuffer = FrameRenderer.render(text: currentText) else { return }

        let pts = CMTime(value: frameCount, timescale: 30)
        frameCount += 1

        guard let sampleBuffer = FrameRenderer.sampleBuffer(from: pixelBuffer, presentationTime: pts) else { return }

        // If the layer is flushed / not ready, reset it before enqueueing.
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        displayLayer.enqueue(sampleBuffer)
    }
}
