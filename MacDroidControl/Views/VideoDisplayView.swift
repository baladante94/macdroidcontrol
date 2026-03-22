#if os(macOS)
import SwiftUI
import AVFoundation
import QuartzCore

/// Wraps AVSampleBufferDisplayLayer in an NSViewRepresentable so SwiftUI
/// can render H.264 frames decoded by H264StreamDecoder with zero-copy GPU output.
struct VideoDisplayView: NSViewRepresentable {
    let decoder: H264StreamDecoder

    func makeNSView(context: Context) -> VideoLayerHost {
        let host = VideoLayerHost()
        // Wire decoder output directly to the display layer — thread-safe.
        decoder.onSampleBuffer = { sb in
            host.displayLayer.enqueue(sb)
        }
        return host
    }

    func updateNSView(_ nsView: VideoLayerHost, context: Context) {
        // No dynamic props to update.
    }
}

// MARK: - NSView hosting AVSampleBufferDisplayLayer

final class VideoLayerHost: NSView {
    let displayLayer = AVSampleBufferDisplayLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        displayLayer.videoGravity  = .resizeAspect
        displayLayer.backgroundColor = CGColor.black
        layer?.addSublayer(displayLayer)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
    }
}
#endif
