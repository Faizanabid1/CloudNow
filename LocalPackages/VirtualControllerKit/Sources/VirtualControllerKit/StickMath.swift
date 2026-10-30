import CoreGraphics
import Foundation

public enum StickMath {
    /// Turns a finger's offset from the stick origin into a vector of length ≤ 1 (screen axes).
    /// The radial dead zone is rescaled away, so output ramps up from zero at the zone's edge
    /// instead of jumping.
    public static func vector(offset: CGVector, radius: CGFloat, deadZone: CGFloat) -> CGVector {
        guard radius > 0 else { return .zero }
        let x = offset.dx / radius
        let y = offset.dy / radius
        let magnitude = hypot(x, y)
        guard magnitude > deadZone, magnitude > 0 else { return .zero }
        let scaled = (min(magnitude, 1) - deadZone) / (1 - deadZone)
        return CGVector(dx: x / magnitude * scaled, dy: y / magnitude * scaled)
    }

    /// Screen y grows downward; XInput's stick y grows upward.
    public static func stickValue(_ vector: CGVector) -> StickValue {
        StickValue(
            x: Int16((vector.dx.clamped(to: -1...1) * 32767).rounded()),
            y: Int16((-vector.dy.clamped(to: -1...1) * 32767).rounded())
        )
    }

    /// Eight-way D-pad: each 45° sector around the center maps to one direction or a diagonal.
    public static func dpadButtons(offset: CGVector, radius: CGFloat, deadZone: CGFloat) -> GamepadButtons {
        guard hypot(offset.dx, offset.dy) > radius * deadZone else { return [] }
        // 0 = right, counter-clockwise, with up positive.
        let angle = atan2(-offset.dy, offset.dx)
        let sector = (Int((angle / (.pi / 4)).rounded()) + 8) % 8
        switch sector {
        case 0: return .dpadRight
        case 1: return [.dpadUp, .dpadRight]
        case 2: return .dpadUp
        case 3: return [.dpadUp, .dpadLeft]
        case 4: return .dpadLeft
        case 5: return [.dpadDown, .dpadLeft]
        case 6: return .dpadDown
        default: return [.dpadDown, .dpadRight]
        }
    }
}
