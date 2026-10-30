import Foundation
@preconcurrency import LiveKitWebRTC
import Synchronization
import VideoToolbox

/// Decoder hardening used by the iPhone/iPad app. Apple TV keeps its original synchronous,
/// rebuild-on-every-change behavior until these paths have been proven on that platform.
nonisolated enum CloudVideoDecoderPolicy {
    #if os(iOS)
        /// Asynchronous decode, malfunction recovery and session reuse across compatible
        /// parameter-set changes, matching LiveKit's shipped VideoToolbox decoders.
        static let enhancedRecovery = true
    #else
        static let enhancedRecovery = false
    #endif

    /// Failed outputs in a row before the decoder session is rebuilt from scratch.
    static let consecutiveFailureLimit = 3

    static var decodeFlags: VTDecodeFrameFlags {
        enhancedRecovery ? [._EnableAsynchronousDecompression] : []
    }

    /// Status codes that mean the session itself is unusable and must be recreated.
    static func requiresSessionRebuild(_ status: OSStatus) -> Bool {
        if status == kVTInvalidSessionErr { return true }
        return enhancedRecovery && status == kVTVideoDecoderMalfunctionErr
    }
}

/// Carries an asynchronous VideoToolbox output error to the next `decode` call, which is
/// the only place a decoder can report failure back to WebRTC.
nonisolated final class DecoderOutputErrorSlot: Sendable {
    private let status = Mutex<OSStatus>(noErr)

    func store(_ newStatus: OSStatus) {
        status.withLock { $0 = newStatus }
    }

    func take() -> OSStatus {
        status.withLock { current in
            let value = current
            current = noErr
            return value
        }
    }
}

/// Cumulative video-pipeline events, always on and cheap enough to count every frame.
/// The stream health log reads these once per second.
nonisolated struct StreamHealthCounterValues: Sendable, Equatable {
    var decoderOutputErrors = 0
    var decoderSessionRebuilds = 0
    var decoderFormatReuses = 0
    var decoderMalfunctions = 0
    var rendererFailures = 0
    var rendererFlushes = 0
    var softwareDecodedFrames = 0
}

nonisolated enum StreamHealthCounters {
    private static let storage = Mutex(StreamHealthCounterValues())

    static func record(_ update: (inout StreamHealthCounterValues) -> Void) {
        storage.withLock { update(&$0) }
    }

    static func snapshot() -> StreamHealthCounterValues {
        storage.withLock { $0 }
    }
}

/// WebRTC's decoder callback, captured per frame by VideoToolbox output handlers. WebRTC
/// allows the callback to be invoked from the decoder's output thread.
nonisolated struct DecoderFrameCallback: @unchecked Sendable {
    let deliver: RTCVideoDecoderCallback?
}
