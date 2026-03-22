#if os(macOS)
import Foundation
import ScreenCaptureKit
import AVFoundation
import AppKit
import Combine

/// Records the scrcpy mirror window using ScreenCaptureKit.
/// No scrcpy restart is needed — this captures whatever is visible on screen.
@MainActor
class MacScreenRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var lastError: String? = nil

    private var stream: SCStream?
    private let writerQueue = DispatchQueue(label: "com.macdroid.recorder", qos: .userInteractive)

    // Accessed from writerQueue only after startCapture() returns.
    nonisolated(unsafe) private var assetWriter: AVAssetWriter?
    nonisolated(unsafe) private var videoInput: AVAssetWriterInput?
    nonisolated(unsafe) private var sessionStarted = false

    // MARK: - Start

    func startRecording(deviceId: String, to url: URL) async {
        guard !isRecording else { return }
        lastError = nil

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            // Prefer the window we titled after this device; fall back to any scrcpy window.
            let targetTitle = "MacDroidControl · \(deviceId)"
            let window = content.windows.first { $0.title == targetTitle }
                      ?? content.windows.first { $0.owningApplication?.applicationName.lowercased() == "scrcpy" }

            guard let window else {
                lastError = "Mirror window not found. Start mirroring first, then record."
                return
            }

            let scale  = Int(NSScreen.main?.backingScaleFactor ?? 2.0)
            let width  = max(Int(window.frame.width)  * scale, 2)
            let height = max(Int(window.frame.height) * scale, 2)

            // AVAssetWriter
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 8_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                ],
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)

            assetWriter    = writer
            videoInput     = input
            sessionStarted = false
            writer.startWriting()

            // SCStream targeting only the scrcpy window
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let cfg = SCStreamConfiguration()
            cfg.width  = width
            cfg.height = height
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            cfg.pixelFormat = kCVPixelFormatType_32BGRA
            cfg.showsCursor = false

            let s = SCStream(filter: filter, configuration: cfg, delegate: self)
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: writerQueue)
            try await s.startCapture()

            stream = s
            isRecording = true
        } catch {
            let msg = error.localizedDescription
            let isPermission = msg.lowercased().contains("permission")
                            || msg.lowercased().contains("denied")
                            || msg.lowercased().contains("declined")
                            || msg.lowercased().contains("not authorized")
            if isPermission {
                lastError = "⚠️ Screen Recording OFF — open System Settings → Privacy & Security → Screen & System Audio Recording → enable MacDroidControl, then relaunch the app."
            } else {
                lastError = "Recording failed: \(msg)"
            }
            assetWriter = nil
            videoInput  = nil
        }
    }

    // MARK: - Stop

    func stopRecording() async {
        guard isRecording else { return }
        isRecording = false

        if let s = stream {
            try? await s.stopCapture()
            stream = nil
        }

        // Finalize the file on the writer queue to let any in-flight appends complete.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writerQueue.async { [weak self] in
                self?.videoInput?.markAsFinished()
                if let writer = self?.assetWriter {
                    writer.finishWriting {
                        Task { @MainActor [weak self] in
                            self?.assetWriter = nil
                            self?.videoInput  = nil
                            continuation.resume()
                        }
                    }
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

// MARK: - SCStreamOutput

extension MacScreenRecorder: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              CMSampleBufferDataIsReady(sampleBuffer),
              let input = videoInput,
              input.isReadyForMoreMediaData else { return }

        if !sessionStarted {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            assetWriter?.startSession(atSourceTime: pts)
            sessionStarted = true
        }
        input.append(sampleBuffer)
    }
}

// MARK: - SCStreamDelegate

extension MacScreenRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.lastError = "Recording stopped: \(error.localizedDescription)"
            self.isRecording = false
        }
    }
}
#endif
