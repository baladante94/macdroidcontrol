#if os(macOS)
import SwiftUI
import AVFoundation

/// Full-screen view that shows the live device mirror.
///
/// - H.264 path (fast): Uses VideoDisplayView → AVSampleBufferDisplayLayer.
/// - Screencap path (fallback): Renders NSImage frames from screencap polling.
///
/// Handles tap, hold, and swipe via DragGesture.
struct MirrorDisplayView: View {
    let device: Device
    @ObservedObject var session: MirrorSession

    private let touch = TouchController()

    @State private var viewSize:          CGSize  = .zero
    @State private var tapIndicator:      CGPoint? = nil
    @State private var pulseRec:          Bool    = false
    @State private var gestureStartTime:  Date?   = nil
    @State private var gestureStartPoint: CGPoint? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                // -- Live content --
                if let decoder = session.h264Decoder {
                    // Fast H.264 path: GPU-rendered via AVSampleBufferDisplayLayer
                    VideoDisplayView(decoder: decoder)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(inputGesture(imageSize: nil, geo: geo))
                } else if let frame = session.currentFrame {
                    // Screencap fallback path
                    liveImage(frame: frame, geo: geo)
                } else {
                    connectingPlaceholder
                }

                overlayControls
            }
            .onAppear  { viewSize = geo.size }
            .onChange(of: geo.size) { _, s in viewSize = s }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: session.isRecording) { _, rec in pulseRec = rec }
    }

    // MARK: - Screencap Image

    private func liveImage(frame: NSImage, geo: GeometryProxy) -> some View {
        Image(nsImage: frame)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay {
                if let pt = tapIndicator {
                    Circle()
                        .stroke(Color.white.opacity(0.75), lineWidth: 1.5)
                        .frame(width: 34, height: 34)
                        .position(pt)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.4)))
                }
            }
            .gesture(inputGesture(imageSize: frame.size, geo: geo))
    }

    // MARK: - Connecting Placeholder

    private var connectingPlaceholder: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.3)
            Text(session.isStreaming ? "Starting H.264 stream…" : "Capturing screen…")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: - Gesture (tap / hold / swipe)

    private func inputGesture(imageSize: CGSize?, geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if gestureStartTime == nil {
                    gestureStartTime  = Date()
                    gestureStartPoint = value.startLocation
                }
            }
            .onEnded { value in
                let elapsed  = Date().timeIntervalSince(gestureStartTime ?? Date())
                let startPt  = gestureStartPoint ?? value.startLocation
                let dx = value.location.x - startPt.x
                let dy = value.location.y - startPt.y
                let dist = (dx * dx + dy * dy).squareRoot()

                gestureStartTime  = nil
                gestureStartPoint = nil

                // In H.264 streaming mode, the video fills the whole view; treat the
                // entire view as device-sized (map 1:1 from view coords to % of screen).
                let fromDC: CGPoint
                let toDC:   CGPoint

                if let imgSize = imageSize {
                    // Screencap path: image is aspect-fitted, need pillar/letterbox offset.
                    guard let f = deviceCoords(tap: startPt,        imageSize: imgSize, viewSize: geo.size),
                          let t = deviceCoords(tap: value.location, imageSize: imgSize, viewSize: geo.size)
                    else { return }
                    fromDC = f; toDC = t
                } else {
                    // H.264 streaming path: map view coords → device pixel coords.
                    let res = session.deviceResolution
                    fromDC = CGPoint(x: startPt.x        / geo.size.width  * res.width,
                                     y: startPt.y        / geo.size.height * res.height)
                    toDC   = CGPoint(x: value.location.x / geo.size.width  * res.width,
                                     y: value.location.y / geo.size.height * res.height)
                }

                showRipple(at: startPt)

                if dist < 8 {
                    if elapsed >= 0.4 {
                        // Long press → hold (zero-movement swipe with elapsed duration)
                        let ms = max(400, Int(elapsed * 1000))
                        Task { await touch.swipe(deviceId: device.id, from: fromDC, to: fromDC, durationMs: ms) }
                    } else {
                        Task { await touch.tap(deviceId: device.id, x: Int(fromDC.x), y: Int(fromDC.y)) }
                    }
                } else {
                    let ms = max(80, Int(elapsed * 1000))
                    Task { await touch.swipe(deviceId: device.id, from: fromDC, to: toDC, durationMs: ms) }
                }
            }
    }

    // MARK: - Overlay (status strip + nav bar)

    private var overlayControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if session.isRecording {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .opacity(pulseRec ? 1 : 0.2)
                            .animation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true), value: pulseRec)
                        Text("REC")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                }

                Spacer()

                if session.isStreaming {
                    Text("H.264")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.green.opacity(0.7))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 5))
                } else if session.measuredFPS > 0 {
                    Text(String(format: "%.1f fps", session.measuredFPS))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Spacer()

            navBar.padding(.bottom, 20)
        }
    }

    // MARK: - Nav Bar

    private var navBar: some View {
        HStack(spacing: 32) {
            navButton(symbol: "chevron.left",       help: "Back")    { await touch.press(.back,    deviceId: device.id) }
            navButton(symbol: "circle.fill", size: 20, help: "Home") { await touch.press(.home,    deviceId: device.id) }
            navButton(symbol: "rectangle.grid.1x2", help: "Recents") { await touch.press(.recents, deviceId: device.id) }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func navButton(
        symbol: String, size: CGFloat = 17, help: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button { Task { await action() } } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Tap Ripple

    private func showRipple(at point: CGPoint) {
        withAnimation(.easeOut(duration: 0.05)) { tapIndicator = point }
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            withAnimation(.easeIn(duration: 0.15)) { tapIndicator = nil }
        }
    }

    // MARK: - Screencap Coordinate Mapping

    private func deviceCoords(tap: CGPoint, imageSize: CGSize, viewSize: CGSize) -> CGPoint? {
        guard viewSize.width > 0, viewSize.height > 0,
              imageSize.width > 0, imageSize.height > 0 else { return nil }

        let imgAsp  = imageSize.width  / imageSize.height
        let viewAsp = viewSize.width   / viewSize.height
        let rendered: CGSize
        let offset:   CGPoint

        if imgAsp < viewAsp {
            let h = viewSize.height; let w = h * imgAsp
            rendered = CGSize(width: w, height: h)
            offset   = CGPoint(x: (viewSize.width - w) / 2, y: 0)
        } else {
            let w = viewSize.width; let h = w / imgAsp
            rendered = CGSize(width: w, height: h)
            offset   = CGPoint(x: 0, y: (viewSize.height - h) / 2)
        }

        let rect = CGRect(origin: offset, size: rendered)
        guard rect.contains(tap) else { return nil }
        return CGPoint(
            x: (tap.x - offset.x) / rendered.width  * imageSize.width,
            y: (tap.y - offset.y) / rendered.height * imageSize.height
        )
    }
}
#endif
