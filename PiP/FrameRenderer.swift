import UIKit
import CoreVideo
import CoreMedia
import CoreText

/// Renders a text string into a CVPixelBuffer at the given resolution.
/// Uses CoreGraphics — no UIKit/SwiftUI main-thread dependency — so it is
/// safe to call from any queue.
enum FrameRenderer {

    static let width:  Int = 1920
    static let height: Int = 1080

    // Pixel-buffer pool shared across renders to avoid repeated alloc/dealloc.
    private static var _pool: CVPixelBufferPool?
    private static let poolLock = NSLock()

    private static func pool() -> CVPixelBufferPool {
        poolLock.lock()
        defer { poolLock.unlock() }
        if let p = _pool { return p }
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey  as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        var p: CVPixelBufferPool!
        CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &p)
        _pool = p
        return p
    }

    /// Render `text` into a new CVPixelBuffer.
    static func render(text: String) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool(), &pixelBuffer)
        guard status == kCVReturnSuccess, let pb = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let context = CGContext(
            data:             CVPixelBufferGetBaseAddress(pb),
            width:            width,
            height:           height,
            bitsPerComponent: 8,
            bytesPerRow:      CVPixelBufferGetBytesPerRow(pb),
            space:            CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:       CGImageAlphaInfo.premultipliedFirst.rawValue |
                              CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Background
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Subtle gradient vignette for polish
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1),
                CGColor(red: 0,    green: 0,    blue: 0,    alpha: 1)
            ] as CFArray,
            locations: [0.0, 1.0]
        ) {
            let center = CGPoint(x: width / 2, y: height / 2)
            context.drawRadialGradient(
                gradient,
                startCenter: center, startRadius: 0,
                endCenter:   center, endRadius:   CGFloat(max(width, height)) * 0.75,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // Measure and draw text using NSAttributedString → CTLine
        let fontSize = dynamicFontSize(for: text)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .heavy),
            .foregroundColor: UIColor.white
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)

        let bounds  = CTLineGetBoundsWithOptions(line, [])
        let originX = (CGFloat(width)  - bounds.width)  / 2 - bounds.origin.x
        let originY = (CGFloat(height) - bounds.height) / 2 - bounds.origin.y

        context.textPosition = CGPoint(x: originX, y: originY)
        CTLineDraw(line, context)

        return pb
    }

    /// Wrap a CVPixelBuffer in a CMSampleBuffer with a presentation timestamp.
    static func sampleBuffer(from pixelBuffer: CVPixelBuffer, presentationTime: CMTime) -> CMSampleBuffer? {
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription
        )
        guard let fmt = formatDescription else { return nil }

        var timingInfo = CMSampleTimingInfo(
            duration:               CMTime(value: 1, timescale: 30),
            presentationTimeStamp:  presentationTime,
            decodeTimeStamp:        .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator:                      nil,
            imageBuffer:                    pixelBuffer,
            dataReady:                      true,
            makeDataReadyCallback:          nil,
            refcon:                         nil,
            formatDescription:             fmt,
            sampleTiming:                  &timingInfo,
            sampleBufferOut:               &sampleBuffer
        )
        return sampleBuffer
    }

    // MARK: - Helpers

    private static func dynamicFontSize(for text: String) -> CGFloat {
        // Shrink font for longer strings so text fits comfortably.
        switch text.count {
        case 0...6:   return 160
        case 7...12:  return 120
        case 13...20: return 90
        default:      return 64
        }
    }
}
