import CoreGraphics
import Foundation

public enum GyroOutputMode: String, Codable, CaseIterable, Sendable {
    case off
    /// Turning the phone moves the remote mouse, for mouse-aim games and launchers.
    case mouse
    /// Turning the phone deflects the right stick, added to any touch on that stick.
    case rightStick
}

public enum GyroActivation: String, Codable, CaseIterable, Sendable {
    case always
    /// Only while the left trigger is held, so the camera stays put outside of aiming.
    case whileAiming
    /// Only while a thumb rests on the right stick; lift it to reposition the phone.
    case whileTouchingRightStick
}

/// Steam Input-style gyro aiming options, saved with each layout.
public struct GyroSettings: Codable, Hashable, Sendable {
    public static let sensitivityRange: ClosedRange<Double> = 0.25...4

    public var mode: GyroOutputMode = .off
    public var activation: GyroActivation = .always
    public var sensitivity: Double = 1
    public var invertHorizontal = false
    public var invertVertical = false

    public init() {}
}

/// A 3D vector in the device's motion-sensor frame.
public struct MotionVector: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    var length: Double { (x * x + y * y + z * z).squareRoot() }

    func dot(_ other: MotionVector) -> Double { x * other.x + y * other.y + z * other.z }

    func cross(_ other: MotionVector) -> MotionVector {
        MotionVector(x: y * other.z - z * other.y, y: z * other.x - x * other.z, z: x * other.y - y * other.x)
    }

    func scaled(_ factor: Double) -> MotionVector {
        MotionVector(x: x * factor, y: y * factor, z: z * factor)
    }
}

/// Converts raw rotation into turns as the player sees them, without assuming how the motion
/// sensor is mounted relative to the screen (on a foldable it can be rotated or flipped
/// against the inner display).
///
/// The screen's axes are learned from gravity when gyro starts and then held fixed, so they
/// can't flip mid-motion. Tilting is rotation about the screen's own horizontal axis, so
/// tilting up and back down by the same amount always cancels. Turning uses Steam's "player
/// space": rotation about real-world up, built only from the screen's turn and roll axes, so
/// it feels like turning your body whether the phone is upright or lying back.
public struct GyroFrame: Sendable {
    /// Screen axes in the sensor frame, once learned.
    private var up: MotionVector?
    private var towardPlayer: MotionVector?

    /// How much turn and roll may be boosted to make up for a tilted grip.
    static let playerSpaceRelax = 1.41

    public init() {}

    /// Forgets the learned axes, e.g. when gyro restarts with the phone held differently.
    public mutating func reset() {
        up = nil
        towardPlayer = nil
    }

    /// - Parameters:
    ///   - rotation: rotation rate in radians per second, sensor frame (Core Motion's
    ///     bias-corrected `rotationRate`).
    ///   - gravity: gravity in g, sensor frame.
    /// - Returns: turn rates in degrees per second; yaw is positive turning right, pitch is
    ///   positive tilting the view up. Zero until the axes are known.
    public mutating func screenRates(rotation: MotionVector, gravity: MotionVector) -> (yaw: CGFloat, pitch: CGFloat) {
        let gravityLength = gravity.length
        guard gravityLength > 0.1 else { return (0, 0) }
        learnAxes(from: gravity, length: gravityLength)
        guard let up, let towardPlayer else { return (0, 0) }
        let right = up.cross(towardPlayer)

        let upRate = rotation.dot(up)
        let rollRate = rotation.dot(towardPlayer)
        let down = gravity.scaled(1 / gravityLength)
        // Rotation about world up, using only the turn and roll axes so tilting never leaks in.
        let worldYaw = -(down.dot(up) * upRate + down.dot(towardPlayer) * rollRate)
        let yawRate = (worldYaw < 0 ? -1 : 1)
            * min(abs(worldYaw) * Self.playerSpaceRelax, (upRate * upRate + rollRate * rollRate).squareRoot())

        let degrees = 180 / Double.pi
        // Turning right is clockwise seen from above: a negative rotation about up. Rotating
        // about right carries the top edge toward the player: looking up.
        return (CGFloat(-yawRate * degrees), CGFloat(rotation.dot(right) * degrees))
    }

    private mutating func learnAxes(from gravity: MotionVector, length: Double) {
        // A player looks down at the screen, so its face tips up and gravity points out the back.
        if towardPlayer == nil, abs(gravity.z) > 0.15 * length {
            towardPlayer = MotionVector(x: 0, y: 0, z: gravity.z < 0 ? 1 : -1)
        }
        // Screen up is opposite gravity along the screen, rounded to the nearest sensor axis.
        let alongScreen = (gravity.x * gravity.x + gravity.y * gravity.y).squareRoot()
        guard alongScreen > 0.25 * length else { return }
        let candidate = abs(gravity.x) > abs(gravity.y)
            ? MotionVector(x: gravity.x < 0 ? 1 : -1, y: 0, z: 0)
            : MotionVector(x: 0, y: gravity.y < 0 ? 1 : -1, z: 0)
        guard let current = up else {
            up = candidate
            return
        }
        // Only turning the phone end over end relearns it; a sideways reading mid-move doesn't.
        if candidate.dot(current) < 0, alongScreen > 0.7 * length {
            up = candidate
        }
    }
}

/// Steam-style tiered smoothing: slow, small motion (where hand tremor lives) is averaged over
/// a short window instead of being discarded, so the total movement is preserved; fast motion
/// passes straight through with no added delay.
public struct GyroSmoother: Sendable {
    /// Below this speed (degrees per second) input is fully smoothed; above `directSpeed`
    /// it's passed straight through, blending in between.
    static let smoothedSpeed: CGFloat = 2
    static let directSpeed: CGFloat = 5
    /// About 65 ms at 120 Hz.
    static let windowLength = 8

    private var window: [(yaw: CGFloat, pitch: CGFloat)] = []

    public init() {}

    public mutating func reset() {
        window = []
    }

    public mutating func smooth(yaw: CGFloat, pitch: CGFloat) -> (yaw: CGFloat, pitch: CGFloat) {
        let speed = hypot(yaw, pitch)
        let directShare = min(max((speed - Self.smoothedSpeed) / (Self.directSpeed - Self.smoothedSpeed), 0), 1)
        window.append((yaw * (1 - directShare), pitch * (1 - directShare)))
        if window.count > Self.windowLength {
            window.removeFirst()
        }
        // Dividing by the full window length (not the samples so far) keeps every sample's
        // total contribution equal to its input once it has passed through the window.
        let count = CGFloat(Self.windowLength)
        let averageYaw = window.reduce(0) { $0 + $1.yaw } / count
        let averagePitch = window.reduce(0) { $0 + $1.pitch } / count
        return (yaw * directShare + averageYaw, pitch * directShare + averagePitch)
    }
}

public enum GyroAiming {
    /// Remote pixels per degree of turn at sensitivity 1.
    static let mousePixelsPerDegree: CGFloat = 8
    /// Turn rate that fully deflects the stick at sensitivity 1.
    static let fullStickDegreesPerSecond: CGFloat = 180
    /// Games ignore small stick movement; output starts just past a typical in-game dead zone
    /// so slow, precise turns still register.
    static let stickDeadZoneCompensation: CGFloat = 0.12
    /// Below this (degrees per second) the stick stays centered. Dead-zone compensation would
    /// otherwise turn a resting hand into a steady camera drift.
    static let stickRestSpeed: CGFloat = 0.75

    /// Mouse motion in remote pixels for one sample (screen axes: +x right, +y down). There's
    /// no dead zone, so tilting up and back down returns the pointer to where it started.
    public static func mouseDelta(
        yaw: CGFloat, pitch: CGFloat, interval: TimeInterval, settings: GyroSettings
    ) -> CGVector {
        let (yaw, pitch) = inverted(settings, yaw: yaw, pitch: pitch)
        let scale = mousePixelsPerDegree * CGFloat(settings.sensitivity) * CGFloat(interval)
        return CGVector(dx: yaw * scale, dy: -pitch * scale)
    }

    /// Stick deflection for the current turn rate (XInput axes: +y up). A stick sets turn
    /// speed rather than position, and games add their own curves, so this mode can't promise
    /// to return to the same spot the way mouse mode does.
    public static func stickValue(yaw: CGFloat, pitch: CGFloat, settings: GyroSettings) -> StickValue {
        let (yaw, pitch) = inverted(settings, yaw: yaw, pitch: pitch)
        let full = fullStickDegreesPerSecond / CGFloat(settings.sensitivity)
        func axis(_ rate: CGFloat) -> CGFloat {
            guard abs(rate) >= stickRestSpeed else { return 0 }
            let magnitude = min(abs(rate) / full, 1)
            let compensated = stickDeadZoneCompensation + (1 - stickDeadZoneCompensation) * magnitude
            return rate < 0 ? -compensated : compensated
        }
        // stickValue expects screen axes (+y down).
        return StickMath.stickValue(CGVector(dx: axis(yaw), dy: -axis(pitch)))
    }

    private static func inverted(_ settings: GyroSettings, yaw: CGFloat, pitch: CGFloat) -> (CGFloat, CGFloat) {
        (settings.invertHorizontal ? -yaw : yaw, settings.invertVertical ? -pitch : pitch)
    }
}

public extension StickValue {
    /// Adds two stick inputs, saturating at the axis limits.
    func adding(_ other: StickValue) -> StickValue {
        StickValue(
            x: Int16(clamping: Int(x) + Int(other.x)),
            y: Int16(clamping: Int(y) + Int(other.y))
        )
    }
}
