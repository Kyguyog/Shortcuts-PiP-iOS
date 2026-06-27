// Rendering/TextFrameRenderer.swift
// Converts a text string → CVPixelBuffer → CMSampleBuffer.
//
// Strategy:
//   1. Create a CGContext backed by a CVPixelBuffer (so we write directly into
//      GPU-accessible memory without an extra copy).
//   2. Draw a solid background + centred NSAttributedString.
//   3. Wrap the pixel buffer in a CMSampleBuffer with a synthetic timestamp.
//
// Thread-safety: all public methods are safe to call from any queue; internal
// CoreVideo/CoreGraphics work is serialised on `renderQueue`.

import AVFoundation
import CoreVideo
import CoreGraphics
import UIKit

final class TextFrameRenderer {

    // MARK: - Configuration

    struct Config {
        var width: Int  = 1280
        var height: Int = 720
        var fps: Double = 30
        var backgroundColor: CGColor = UIColor.black.cgColor
        var textColor: UIColor       = .white
        var font: UIFont             = .boldSystemFont(ofSize: 96)
    }

    // MARK: - Private state

    private let config: Config
    private let renderQueue = DispatchQueue(label: "pip.render", qos: .userInteractive)
    private var pixelBufferPool: CVPixelBufferPool?
    private var frameIndex: Int64 = 0

    // MARK: - Init

    init(config: Config = .init()) {
        self.config = config
        setupPool()
    }

    // MARK: - Public API

    /// Render `text` into a fresh CMSampleBuffer.
    /// Returns nil only on catastrophic CVPixelBuffer allocation failure.
    func makeSampleBuffer(text: String) -> CMSampleBuffer? {
        renderQueue.sync {
            guard let pool = pixelBufferPool else { return nil }

            // 1. Allocate pixel buffer from pool (avoids malloc pressure).
            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
            guard status == kCVReturnSuccess, let pb = pixelBuffer else {
                print("⚠️  CVPixelBufferPool alloc failed: \(status)")
                return nil
            }

            // 2. Draw into the pixel buffer.
            draw(text: text, into: pb)

            // 3. Wrap in a sample buffer.
            return wrapInSampleBuffer(pb)
        }
    }

    // MARK: - Private: pool setup

    private func setupPool() {
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey  as String: config.width,
            kCVPixelBufferHeightKey as String: config.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        let poolAttrs: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault,
                                poolAttrs as CFDictionary,
                                attrs as CFDictionary,
                                &pool)
        pixelBufferPool = pool
    }

    // MARK: - Private: draw

    private func draw(text: String, into pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddr = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: baseAddr,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue |
                        CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        let bounds = CGRect(x: 0, y: 0, width: w, height: h)

        // --- Background ---
        ctx.setFillColor(config.backgroundColor)
        ctx.fill(bounds)

        // --- Text (via UIGraphicsPushContext so NSAttributedString works) ---
        UIGraphicsPushContext(ctx)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attrs: [NSAttributedString.Key: Any] = [
            .font:            config.font,
            .foregroundColor: config.textColor,
            .paragraphStyle:  paragraphStyle,
        ]

        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrStr.boundingRect(
            with: CGSize(width: CGFloat(w) * 0.9, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).size

        // CoreGraphics Y-axis is flipped vs UIKit, but UIGraphicsPushContext corrects this.
        let textOrigin = CGPoint(
            x: (CGFloat(w) - textSize.width)  / 2,
            y: (CGFloat(h) - textSize.height) / 2
        )
        let textRect = CGRect(origin: textOrigin, size: textSize)

        // Draw a subtle shadow for legibility.
        ctx.setShadow(offset: CGSize(width: 2, height: -2),
                      blur: 8,
                      color: UIColor.black.withAlphaComponent(0.8).cgColor)

        attrStr.draw(in: textRect)
        UIGraphicsPopContext()
    }

    // MARK: - Private: sample buffer wrapping

    private func wrapInSampleBuffer(_ pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        // Synthetic presentation timestamp. For AVSampleBufferDisplayLayer the
        // actual PTS matters less than the fact it is strictly monotonically increasing.
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(config.fps))
        let pts = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
        frameIndex += 1

        var timingInfo = CMSampleTimingInfo(
            duration:               frameDuration,
            presentationTimeStamp:  pts,
            decodeTimeStamp:        .invalid
        )

        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDesc
        )
        guard let fmt = formatDesc else { return nil }

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator:                kCFAllocatorDefault,
            imageBuffer:              pixelBuffer,
            formatDescription:        fmt,
            sampleTiming:             &timingInfo,
            sampleBufferOut:          &sampleBuffer
        )
        return sampleBuffer
    }
}
