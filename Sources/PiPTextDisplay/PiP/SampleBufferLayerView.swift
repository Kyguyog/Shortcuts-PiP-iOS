// PiP/SampleBufferLayerView.swift
// A thin UIViewRepresentable that exposes the AVSampleBufferDisplayLayer
// as a SwiftUI view. PiP requires the layer to be part of the on-screen
// hierarchy before `startPictureInPicture()` is called.

import SwiftUI
import AVFoundation

struct SampleBufferLayerView: UIViewRepresentable {

    let layer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> SampleBufferHostView {
        let view = SampleBufferHostView()
        view.hostedLayer = layer
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: SampleBufferHostView, context: Context) {}
}

// MARK: - Host UIView

final class SampleBufferHostView: UIView {

    var hostedLayer: AVSampleBufferDisplayLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let l = hostedLayer {
                layer.addSublayer(l)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hostedLayer?.frame = bounds
    }
}
