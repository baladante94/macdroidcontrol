#if os(macOS)
import Foundation
import CoreMedia
import AVFoundation
import VideoToolbox

/// Parses a streaming H.264 Annex B bitstream from `adb exec-out screenrecord`
/// and delivers CMSampleBuffers to an AVSampleBufferDisplayLayer.
///
/// All NAL parsing and CMSampleBuffer construction happen on an internal serial
/// queue; only the `onSampleBuffer` call-back reaches the caller (who is
/// responsible for dispatching to the display layer on the correct thread).
final class H264StreamDecoder {

    /// Called on the internal queue each time a decodable frame is ready.
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    private var accumulator      = Data()
    private var formatDescription: CMVideoFormatDescription?
    private var spsData: Data?
    private var ppsData: Data?
    private let queue = DispatchQueue(label: "com.macdroidcontrol.h264", qos: .userInteractive)

    // MARK: - Feed

    func feed(_ data: Data) {
        queue.async { [weak self] in
            self?.accumulator.append(data)
            self?.drain()
        }
    }

    func reset() {
        queue.async { [weak self] in
            self?.accumulator      = Data()
            self?.formatDescription = nil
            self?.spsData = nil
            self?.ppsData = nil
        }
    }

    // MARK: - NAL Unit Extraction

    private func drain() {
        // Collect every start-code position up front.
        var codes: [(offset: Int, len: Int)] = []
        var i = 0
        let buf = accumulator
        while i + 3 <= buf.count {
            if buf[i] == 0, buf[i+1] == 0 {
                if buf[i+2] == 1 { codes.append((i, 3)); i += 3; continue }
                if i + 3 < buf.count, buf[i+2] == 0, buf[i+3] == 1 {
                    codes.append((i, 4)); i += 4; continue
                }
            }
            i += 1
        }

        guard codes.count >= 2 else {
            // Keep only data from the last start code onwards (if any).
            if let last = codes.first, last.offset > 0 {
                accumulator = Data(buf[last.offset...])
            }
            return
        }

        // Process all complete NAL units (each pair of adjacent start codes defines one).
        for k in 0 ..< codes.count - 1 {
            let bodyStart = codes[k].offset + codes[k].len
            let bodyEnd   = codes[k+1].offset
            guard bodyEnd > bodyStart else { continue }
            process(Data(buf[bodyStart ..< bodyEnd]))
        }

        // Retain everything from the last start code (incomplete trailing NAL).
        let tail = codes[codes.count - 1].offset
        accumulator = tail < buf.count ? Data(buf[tail...]) : Data()
    }

    // MARK: - NAL Processing

    private func process(_ nal: Data) {
        guard !nal.isEmpty else { return }
        let type = nal[0] & 0x1F
        switch type {
        case 7: spsData = nal; tryBuildFormatDescription()
        case 8: ppsData = nal; tryBuildFormatDescription()
        case 1, 5: enqueue(nal)          // non-IDR / IDR
        default:   break
        }
    }

    // MARK: - CMVideoFormatDescription

    private func tryBuildFormatDescription() {
        guard let sps = spsData, let pps = ppsData else { return }
        let spsBytes = [UInt8](sps)
        let ppsBytes = [UInt8](pps)
        var desc: CMVideoFormatDescription?

        spsBytes.withUnsafeBufferPointer { spsBuf in
            ppsBytes.withUnsafeBufferPointer { ppsBuf in
                guard let sp = spsBuf.baseAddress, let pp = ppsBuf.baseAddress else { return }
                var ptrs: [UnsafePointer<UInt8>] = [sp, pp]
                var sizes: [Int] = [spsBytes.count, ppsBytes.count]
                CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: nil,
                    parameterSetCount: 2,
                    parameterSetPointers: &ptrs,
                    parameterSetSizes: &sizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &desc
                )
            }
        }
        if let d = desc { formatDescription = d }
    }

    // MARK: - CMSampleBuffer

    private func enqueue(_ nalBody: Data) {
        guard let fmtDesc = formatDescription else { return }

        // Annex B → AVCC: prepend 4-byte big-endian length instead of start code.
        var avcc = Data(capacity: 4 + nalBody.count)
        var len  = UInt32(nalBody.count).bigEndian
        withUnsafeBytes(of: &len) { avcc.append(contentsOf: $0) }
        avcc.append(nalBody)

        // Allocate a CMBlockBuffer and copy data into it.
        var blockBuffer: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: nil,
            memoryBlock: nil,        // CMBlockBuffer allocates its own memory
            blockLength: avcc.count,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avcc.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let bb = blockBuffer else { return }
        avcc.withUnsafeBytes { ptr in
            CMBlockBufferReplaceDataBytes(
                with: ptr.baseAddress!,
                blockBuffer: bb,
                offsetIntoDestination: 0,
                dataLength: avcc.count
            )
        }

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        CMSampleBufferCreateReady(
            allocator: nil,
            dataBuffer: bb,
            formatDescription: fmtDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard let sb = sampleBuffer else { return }

        // Mark for immediate display (no timestamp-based scheduling).
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true) as? [NSMutableDictionary] {
            attachments.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
        }

        onSampleBuffer?(sb)
    }
}
#endif
