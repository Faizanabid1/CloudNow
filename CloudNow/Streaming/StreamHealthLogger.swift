import Foundation
import os
import QuartzCore
import UIKit

private nonisolated let healthLog = Logger(subsystem: "com.owenselles.CloudNow2", category: "StreamHealth")

/// Device-side conditions sampled once per second during a stream.
nonisolated struct StreamDeviceHealth: Equatable {
    var displayRefreshHz: Double = 0
    var mainThreadMaxGapMs: Double = 0
    var thermalState: String = ""
    var lowPowerMode = false
    var decoderRebuilds = 0
    var decoderErrors = 0
    var rendererFailures = 0
    var softwareDecodedFrames = 0
}

/// Records one CSV row per second for every iPhone/iPad stream so freezes can be traced to
/// the network, the decoder, the renderer or the device afterwards. Rows are written as they
/// are produced, so a log survives the app being closed mid-stream. Inactive on Apple TV.
@MainActor
final class StreamHealthLogger {
    static let shared = StreamHealthLogger()

    #if os(iOS)
        static let isEnabled = true
    #else
        static let isEnabled = false
    #endif

    private static let maximumLogFiles = 10
    private static let header = [
        "time", "elapsed_s", "fps", "game_fps", "width", "height", "bitrate_mbps", "available_mbps",
        "loss_pct", "rtt_ms", "jitter_ms", "jitter_buffer_ms", "jitter_target_ms", "decode_ms",
        "processing_ms", "dropped", "freezes", "freeze_ms", "nack", "pli", "retransmits",
        "decoder", "display_hz", "ui_max_gap_ms", "thermal", "low_power", "decoder_errors",
        "decoder_rebuilds", "decoder_reuses", "decoder_malfunctions", "renderer_failures",
        "renderer_flushes", "software_frames",
    ].joined(separator: ",")

    private var writer: HealthLogWriter?
    private var sessionStartedAt: Date?
    private var baseline = StreamHealthCounterValues()
    private var lastThermalState: ProcessInfo.ThermalState?
    private var lastLowPowerMode: Bool?
    private let displayMonitor = DisplayRateMonitor()
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private init() {}

    static var directory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("StreamHealth", isDirectory: true)
    }

    /// Saved logs, newest first.
    static func logFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return files
            .filter { $0.pathExtension == "csv" }
            .sorted { modificationDate($0) > modificationDate($1) }
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    /// Starts a new log file and the display-rate monitor for a stream.
    func beginSession(summary: [String], preferredFrameRate: Int) {
        guard Self.isEnabled else { return }
        endSession()
        let now = Date()
        let nameFormatter = DateFormatter()
        nameFormatter.locale = Locale(identifier: "en_US_POSIX")
        nameFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let url = Self.directory.appendingPathComponent("stream-health_\(nameFormatter.string(from: now)).csv")
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            Self.pruneOldLogs()
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            writer = try HealthLogWriter(url: url)
        } catch {
            healthLog.error("Could not create stream health log: \(error.localizedDescription, privacy: .public)")
            writer = nil
            return
        }
        sessionStartedAt = now
        baseline = StreamHealthCounters.snapshot()
        lastThermalState = nil
        lastLowPowerMode = nil
        let build = {
            #if DEBUG
                "Debug"
            #else
                "Release"
            #endif
        }()
        var lines = ["# GeForce Now Duo stream health log", "# started \(now.formatted(.iso8601))", "# build \(build)"]
        lines += summary.map { "# \($0)" }
        lines.append(Self.header)
        writer?.append(lines.joined(separator: "\n") + "\n")
        displayMonitor.start(preferredFrameRate: preferredFrameRate)
        healthLog.info("Stream health log started: \(url.lastPathComponent, privacy: .public)")
    }

    /// Adds a timestamped event line, e.g. an ICE state change.
    func note(_ message: String) {
        guard Self.isEnabled, writer != nil else { return }
        writer?.append("# \(timeFormatter.string(from: Date())) \(elapsedSeconds()) s: \(message)\n")
    }

    /// Fills device-side fields for the HUD and appends one row for this stats tick.
    func sample(into stats: inout StreamStats) {
        guard Self.isEnabled, sessionStartedAt != nil else { return }
        let processInfo = ProcessInfo.processInfo
        let thermal = processInfo.thermalState
        let lowPower = processInfo.isLowPowerModeEnabled
        if let lastThermalState, lastThermalState != thermal {
            note("thermal state \(Self.label(lastThermalState)) -> \(Self.label(thermal))")
        }
        if let lastLowPowerMode, lastLowPowerMode != lowPower {
            note("Low Power Mode \(lowPower ? "on" : "off")")
        }
        lastThermalState = thermal
        lastLowPowerMode = lowPower

        let counters = StreamHealthCounters.snapshot()
        let errors = counters.decoderOutputErrors - baseline.decoderOutputErrors
        let rebuilds = counters.decoderSessionRebuilds - baseline.decoderSessionRebuilds
        let reuses = counters.decoderFormatReuses - baseline.decoderFormatReuses
        let malfunctions = counters.decoderMalfunctions - baseline.decoderMalfunctions
        let rendererFailures = counters.rendererFailures - baseline.rendererFailures
        let rendererFlushes = counters.rendererFlushes - baseline.rendererFlushes
        let softwareFrames = counters.softwareDecodedFrames - baseline.softwareDecodedFrames

        stats.device = StreamDeviceHealth(
            displayRefreshHz: displayMonitor.measuredHz,
            mainThreadMaxGapMs: displayMonitor.maxGapMs,
            thermalState: Self.label(thermal),
            lowPowerMode: lowPower,
            decoderRebuilds: rebuilds,
            decoderErrors: errors,
            rendererFailures: rendererFailures,
            softwareDecodedFrames: softwareFrames
        )

        let fields: [String] = [
            timeFormatter.string(from: Date()),
            elapsedSeconds(),
            Self.format(stats.fps, 1),
            Self.format(stats.gameFps, 1),
            String(stats.resolutionWidth),
            String(stats.resolutionHeight),
            Self.format(Double(stats.bitrateKbps) / 1000, 1),
            Self.format(Double(stats.availableIncomingBitrateKbps) / 1000, 1),
            Self.format(stats.packetLossPercent, 2),
            Self.format(stats.rttMs, 1),
            Self.format(stats.jitterMs, 1),
            Self.format(stats.jitterBufferDelayMs, 1),
            Self.format(stats.jitterBufferTargetDelayMs, 1),
            Self.format(stats.decodeTimeMs, 2),
            Self.format(stats.processingDelayMs, 2),
            String(stats.framesDropped),
            String(stats.freezeCount),
            Self.format(stats.freezeDurationMs, 0),
            String(stats.nackCount),
            String(stats.pliCount),
            String(stats.retransmittedPackets),
            stats.decoderImplementation.replacingOccurrences(of: ",", with: " "),
            Self.format(displayMonitor.measuredHz, 1),
            Self.format(displayMonitor.maxGapMs, 1),
            Self.label(thermal),
            lowPower ? "1" : "0",
            String(errors),
            String(rebuilds),
            String(reuses),
            String(malfunctions),
            String(rendererFailures),
            String(rendererFlushes),
            String(softwareFrames),
        ]
        writer?.append(fields.joined(separator: ",") + "\n")
    }

    func endSession() {
        guard Self.isEnabled else { return }
        displayMonitor.stop()
        if writer != nil {
            note("stream ended")
        }
        writer?.close()
        writer = nil
        sessionStartedAt = nil
    }

    private func elapsedSeconds() -> String {
        guard let sessionStartedAt else { return "0" }
        return String(Int(Date().timeIntervalSince(sessionStartedAt).rounded()))
    }

    private static func pruneOldLogs() {
        let files = logFiles()
        guard files.count >= maximumLogFiles else { return }
        for file in files.dropFirst(maximumLogFiles - 1) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func format(_ value: Double, _ digits: Int) -> String {
        guard value.isFinite else { return "" }
        return String(format: "%.\(digits)f", value)
    }

    static func label(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}

/// Appends text to the log file on a utility queue so the main thread never waits on disk.
private nonisolated final class HealthLogWriter: @unchecked Sendable {
    private let handle: FileHandle
    private let queue = DispatchQueue(label: "com.cloudnow.stream-health-log", qos: .utility)

    init(url: URL) throws {
        handle = try FileHandle(forWritingTo: url)
    }

    func append(_ text: String) {
        let data = Data(text.utf8)
        queue.async { [handle] in
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    func close() {
        queue.async { [handle] in
            try? handle.close()
        }
    }
}

/// Measures the refresh rate the app actually gets and the longest main-thread gap, and asks
/// the system to keep the display at the stream's frame rate. Without a frame-rate request,
/// ProMotion iPhones may hold the app at 60 Hz and show only every other frame of a 120 fps
/// stream.
@MainActor
private final class DisplayRateMonitor: NSObject {
    private var link: CADisplayLink?
    private var windowStart: CFTimeInterval = 0
    private var lastTimestamp: CFTimeInterval = 0
    private var framesInWindow = 0
    private var largestGap: CFTimeInterval = 0
    private(set) var measuredHz: Double = 0
    private(set) var maxGapMs: Double = 0

    func start(preferredFrameRate: Int) {
        stop()
        let screenMaximum = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.maximumFramesPerSecond }
            .max() ?? 60
        let maximum = Float(max(screenMaximum, 60))
        let preferred = min(Float(max(preferredFrameRate, 30)), maximum)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: min(60, preferred),
            maximum: maximum,
            preferred: preferred
        )
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        windowStart = 0
        lastTimestamp = 0
        framesInWindow = 0
        largestGap = 0
        measuredHz = 0
        maxGapMs = 0
    }

    @objc private func tick(_ link: CADisplayLink) {
        let timestamp = link.timestamp
        guard windowStart > 0 else {
            windowStart = timestamp
            lastTimestamp = timestamp
            return
        }
        framesInWindow += 1
        largestGap = max(largestGap, timestamp - lastTimestamp)
        lastTimestamp = timestamp
        let elapsed = timestamp - windowStart
        guard elapsed >= 1 else { return }
        measuredHz = Double(framesInWindow) / elapsed
        maxGapMs = largestGap * 1000
        windowStart = timestamp
        framesInWindow = 0
        largestGap = 0
    }
}
