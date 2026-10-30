import CoreGraphics
import Foundation

public enum MouseButton: Hashable, Sendable {
    case left, middle, right
}

public enum TrackpadEvent: Equatable, Sendable {
    /// Relative pointer motion in remote pixels.
    case move(dx: CGFloat, dy: CGFloat)
    /// Wheel motion; negative scrolls content down, matching a finger pushing it up.
    case scroll(dy: CGFloat)
    case button(MouseButton, pressed: Bool)
}

/// Turns touches that miss every control into laptop-trackpad input: drag to move the pointer,
/// tap to left-click, two-finger tap to right-click, two-finger drag to scroll, and tap then
/// touch again to hold the left button while dragging.
public struct TrackpadGestures<TouchID: Hashable> {
    /// Remote pixels per point of finger travel.
    public var pointerSpeed: CGFloat = 2.5
    /// Wheel units per point of two-finger travel.
    public var scrollSpeed: CGFloat = 4

    static var tapMovement: CGFloat { 10 }
    static var tapDuration: TimeInterval { 0.3 }
    static var dragWindow: TimeInterval { 0.3 }

    private var fingers: [TouchID: CGPoint] = [:]
    private var gestureStart: TimeInterval = 0
    private var gestureFingerCount = 0
    private var gestureTravel: CGFloat = 0
    private var lastTapEnd: TimeInterval?
    private var isDragging = false

    public init() {}

    public mutating func began(_ touch: TouchID, at point: CGPoint, time: TimeInterval) -> [TrackpadEvent] {
        var events: [TrackpadEvent] = []
        if fingers.isEmpty {
            gestureStart = time
            gestureFingerCount = 0
            gestureTravel = 0
            if let lastTapEnd, time - lastTapEnd <= Self.dragWindow {
                isDragging = true
                events.append(.button(.left, pressed: true))
            }
            lastTapEnd = nil
        }
        fingers[touch] = point
        gestureFingerCount = max(gestureFingerCount, fingers.count)
        return events
    }

    public mutating func moved(_ touch: TouchID, to point: CGPoint, time: TimeInterval) -> [TrackpadEvent] {
        guard let last = fingers[touch] else { return [] }
        fingers[touch] = point
        let dx = point.x - last.x
        let dy = point.y - last.y
        gestureTravel += hypot(dx, dy)
        if fingers.count == 1 {
            return [.move(dx: dx * pointerSpeed, dy: dy * pointerSpeed)]
        }
        // Each finger reports the same swipe, so share the scroll between them.
        return [.scroll(dy: dy * scrollSpeed / CGFloat(fingers.count))]
    }

    public mutating func ended(_ touch: TouchID, time: TimeInterval) -> [TrackpadEvent] {
        guard fingers.removeValue(forKey: touch) != nil, fingers.isEmpty else { return [] }
        if isDragging {
            isDragging = false
            return [.button(.left, pressed: false)]
        }
        guard gestureTravel <= Self.tapMovement, time - gestureStart <= Self.tapDuration else { return [] }
        let button: MouseButton = gestureFingerCount >= 2 ? .right : .left
        if button == .left {
            lastTapEnd = time
        }
        return [.button(button, pressed: true), .button(button, pressed: false)]
    }

    /// Forgets all fingers, releasing a held drag button.
    public mutating func reset() -> [TrackpadEvent] {
        fingers = [:]
        lastTapEnd = nil
        guard isDragging else { return [] }
        isDragging = false
        return [.button(.left, pressed: false)]
    }
}
