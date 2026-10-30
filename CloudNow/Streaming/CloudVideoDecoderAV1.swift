import CoreMedia
import Foundation
@preconcurrency import LiveKitWebRTC
import os.log
import Synchronization
import VideoToolbox

private nonisolated let av1Log = Logger(subsystem: "com.owenselles.CloudNow2", category: "AV1Decoder")

/// Native AV1 decoding for devices that report VideoToolbox hardware support.
/// Devices without that support use LiveKit's software decoder directly from the factory.
/// WebRTC serializes decoder lifecycle calls. Output handlers capture only immutable
/// per-frame values plus a lock-protected error slot, so asynchronous decode is safe.
/// The unchecked conformance bridges that contract until the Objective-C decoder protocol can express its queue isolation.
final nonisolated class CloudVideoDecoderAV1: NSObject, LKRTCVideoDecoder, @unchecked Sendable {
    private var callback: RTCVideoDecoderCallback?
    private var configuration: AV1StreamConfiguration?
    private var videoFormat: CMVideoFormatDescription?
    private var session: VTDecompressionSession?
    /// Asynchronous output failures surface on the following `decode` call.
    private let outputError = DecoderOutputErrorSlot()
    private var consecutiveFailures = 0

    func setCallback(_ callback: @escaping RTCVideoDecoderCallback) {
        self.callback = callback
    }

    func startDecode(withNumberOfCores _: Int32) -> NSInteger {
        0
    }

    func release() -> NSInteger {
        destroySession()
        configuration = nil
        videoFormat = nil
        consecutiveFailures = 0
        _ = outputError.take()
        callback = nil
        return 0
    }

    func implementationName() -> String {
        "VideoToolboxAV1"
    }

    func decode(
        _ encodedImage: LKRTCEncodedImage,
        missingFrames _: Bool,
        codecSpecificInfo _: (any LKRTCCodecSpecificInfo)?,
        renderTimeMs _: Int64
    ) -> NSInteger {
        let enhanced = CloudVideoDecoderPolicy.enhancedRecovery
        let data = encodedImage.buffer
        guard !data.isEmpty else { return -1 }
        if enhanced, !handlePreviousOutputError(isKeyframe: encodedImage.frameType == .videoFrameKey) {
            return -1
        }
        do {
            if let next = try AV1StreamConfiguration.parse(from: data), next != configuration {
                guard let format = Self.makeFormatDescription(configuration: next) else { return -1 }
                if enhanced, let session,
                   VTDecompressionSessionCanAcceptFormatDescription(session, formatDescription: format)
                {
                    StreamHealthCounters.record { $0.decoderFormatReuses += 1 }
                    av1Log.info("Configuration changed; session reused")
                } else {
                    if session != nil {
                        StreamHealthCounters.record { $0.decoderSessionRebuilds += 1 }
                        av1Log.info("Configuration changed; session rebuilt")
                    }
                    destroySession()
                }
                configuration = next
                videoFormat = format
            }
        } catch {
            av1Log.error("Invalid AV1 configuration: \(error)")
            return -1
        }
        // A late join needs a sequence header from a keyframe before decoding can start.
        guard let videoFormat else { return -1 }
        if session == nil, !createSession(format: videoFormat) {
            return -1
        }
        guard let session, let sample = Self.makeSampleBuffer(data: data, format: videoFormat) else {
            return -1
        }

        let timestamp = Int32(bitPattern: encodedImage.timeStamp)
        let rotation = encodedImage.rotation
        let decodeFailed = Mutex(false)
        let frameCallback = DecoderFrameCallback(deliver: callback)
        let outputError = outputError
        let handler: VTDecompressionOutputHandler = { status, _, imageBuffer, _, _ in
            guard status == noErr else {
                av1Log.error("Decode output failed: \(status)")
                decodeFailed.withLock { $0 = true }
                if enhanced {
                    StreamHealthCounters.record { $0.decoderOutputErrors += 1 }
                    outputError.store(status)
                }
                return
            }
            guard let imageBuffer else { return }
            let frame = LKRTCVideoFrame(
                buffer: LKRTCCVPixelBuffer(pixelBuffer: imageBuffer),
                rotation: rotation,
                timeStampNs: 0
            )
            frame.timeStamp = timestamp
            frameCallback.deliver?(frame)
        }
        // Each output handler captures its own frame's timestamp, so asynchronous decode on
        // iOS keeps the WebRTC association. Apple TV keeps the synchronous path.
        let flags = CloudVideoDecoderPolicy.decodeFlags
        var status = VTDecompressionSessionDecodeFrame(
            session, sampleBuffer: sample, flags: flags, infoFlagsOut: nil, outputHandler: handler
        )
        if CloudVideoDecoderPolicy.requiresSessionRebuild(status) {
            av1Log.error("Session unusable (\(status)); rebuilding")
            if status == kVTVideoDecoderMalfunctionErr {
                StreamHealthCounters.record { $0.decoderMalfunctions += 1 }
            }
            StreamHealthCounters.record { $0.decoderSessionRebuilds += 1 }
            destroySession()
            guard createSession(format: videoFormat), let retrySession = self.session else { return -1 }
            status = VTDecompressionSessionDecodeFrame(
                retrySession, sampleBuffer: sample, flags: flags, infoFlagsOut: nil, outputHandler: handler
            )
        }
        if status != noErr || (!enhanced && decodeFailed.withLock({ $0 })) {
            av1Log.error("Decode failed: \(status)")
            if enhanced { StreamHealthCounters.record { $0.decoderOutputErrors += 1 } }
            return -1
        }
        return 0
    }

    /// Applies an asynchronous output failure from an earlier frame. Returns false when this
    /// frame should not be decoded (a delta frame after a failure needs a fresh keyframe).
    private func handlePreviousOutputError(isKeyframe: Bool) -> Bool {
        let previous = outputError.take()
        guard previous != noErr else {
            consecutiveFailures = 0
            return true
        }
        consecutiveFailures += 1
        if previous == kVTVideoDecoderMalfunctionErr
            || previous == kVTInvalidSessionErr
            || consecutiveFailures >= CloudVideoDecoderPolicy.consecutiveFailureLimit
        {
            av1Log.error("Rebuilding session after \(self.consecutiveFailures) failure(s), last \(previous)")
            if previous == kVTVideoDecoderMalfunctionErr {
                StreamHealthCounters.record { $0.decoderMalfunctions += 1 }
            }
            StreamHealthCounters.record { $0.decoderSessionRebuilds += 1 }
            destroySession()
            consecutiveFailures = 0
        }
        return isKeyframe
    }

    private func createSession(format: CMVideoFormatDescription) -> Bool {
        let specification = [kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder: true]
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        var newSession: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: format,
            decoderSpecification: specification as CFDictionary,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &newSession
        )
        guard status == noErr, let newSession else {
            av1Log.error("Hardware session creation failed: \(status)")
            return false
        }
        VTSessionSetProperty(newSession, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        session = newSession
        return true
    }

    private func destroySession() {
        if let session {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
    }

    static func makeFormatDescription(configuration: AV1StreamConfiguration) -> CMVideoFormatDescription? {
        let extensions: [CFString: Any] = [
            kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms: [
                "av1C": configuration.codecConfigurationRecord,
            ],
        ]
        var format: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_AV1,
            width: configuration.width,
            height: configuration.height,
            extensions: extensions as CFDictionary,
            formatDescriptionOut: &format
        )
        guard status == noErr else {
            av1Log.error("Format description creation failed: \(status)")
            return nil
        }
        return format
    }

    /// CoreMedia owns the copied sample for the entire VideoToolbox decode call.
    static func makeSampleBuffer(data: Data, format: CMVideoFormatDescription) -> CMSampleBuffer? {
        guard !data.isEmpty else { return nil }
        var block: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: data.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: data.count,
            flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block
        )
        guard status == noErr, let block else { return nil }
        let copyStatus = data.withUnsafeBytes { bytes -> OSStatus in
            guard let address = bytes.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
            return CMBlockBufferReplaceDataBytes(with: address, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count)
        }
        guard copyStatus == noErr else { return nil }
        var sample: CMSampleBuffer?
        var sampleSize = data.count
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sample
        )
        return sampleStatus == noErr ? sample : nil
    }
}
