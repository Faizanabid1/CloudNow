import CoreGraphics
import Foundation

/// How to draw a stick that a finger is holding.
public struct StickVisual: Hashable, Sendable {
    /// Where the stick's base sits relative to the control's center. Non-zero only for
    /// floating sticks.
    public var baseOffset: CGVector
    /// Knob position inside the base, length ≤ 1, screen axes.
    public var knob: CGVector
}

/// Turns raw multi-touch events into gamepad state. Each finger owns the control it
/// landed on until it lifts, so several controls can be held at once.
public struct TouchInputProcessor<TouchID: Hashable> {
    private struct Contact {
        var elementID: UUID
        var origin: CGPoint
        var location: CGPoint
        var order: Int
    }

    private var contacts: [TouchID: Contact] = [:]
    private var nextOrder = 0

    public var stickDeadZone: CGFloat = 0.12
    public var dpadDeadZone: CGFloat = 0.25
    /// Full stick deflection is reached this far from the origin, as a fraction of the
    /// control's width.
    public var stickTravel: CGFloat = 0.4

    public private(set) var state = GamepadState()
    public private(set) var activeElements: Set<UUID> = []
    public private(set) var sticks: [UUID: StickVisual] = [:]

    public init() {}

    /// Returns false when the touch missed every control, so the caller can use it elsewhere.
    @discardableResult
    public mutating func began(_ touch: TouchID, at point: CGPoint, layout: ControllerLayout, bounds: CGSize) -> Bool {
        guard let element = layout.element(at: point, in: bounds) else { return false }
        let frame = element.frame(in: bounds)
        let origin: CGPoint
        if case .stick = element.kind, layout.floatingSticks {
            origin = point
        } else {
            origin = CGPoint(x: frame.midX, y: frame.midY)
        }
        contacts[touch] = Contact(elementID: element.id, origin: origin, location: point, order: nextOrder)
        nextOrder += 1
        update(layout: layout, bounds: bounds)
        return true
    }

    public mutating func moved(_ touch: TouchID, to point: CGPoint, layout: ControllerLayout, bounds: CGSize) {
        guard var contact = contacts[touch] else { return }
        contact.location = point
        // Sliding a finger from one button onto another rolls the press over, like rocking a
        // thumb across a physical pad's face buttons.
        if case .button = layout[contact.elementID]?.kind,
           let other = layout.element(at: point, in: bounds),
           other.id != contact.elementID,
           case .button = other.kind {
            let frame = other.frame(in: bounds)
            contact.elementID = other.id
            contact.origin = CGPoint(x: frame.midX, y: frame.midY)
        }
        contacts[touch] = contact
        update(layout: layout, bounds: bounds)
    }

    public mutating func ended(_ touch: TouchID, layout: ControllerLayout, bounds: CGSize) {
        guard contacts.removeValue(forKey: touch) != nil else { return }
        update(layout: layout, bounds: bounds)
    }

    public mutating func reset() {
        contacts = [:]
        state = GamepadState()
        activeElements = []
        sticks = [:]
    }

    /// Rebuilds the state from scratch so releasing one of two fingers on the same button
    /// leaves it held.
    private mutating func update(layout: ControllerLayout, bounds: CGSize) {
        var state = GamepadState()
        var active = Set<UUID>()
        var sticks = [UUID: StickVisual]()

        // Oldest first, so the newest finger on a shared stick wins.
        for contact in contacts.values.sorted(by: { $0.order < $1.order }) {
            guard let element = layout[contact.elementID] else { continue }
            active.insert(element.id)
            let frame = element.frame(in: bounds)
            let offset = CGVector(dx: contact.location.x - contact.origin.x, dy: contact.location.y - contact.origin.y)

            switch element.kind {
            case .button(let id):
                state.buttons.insert(id.gamepadButton)
            case .trigger(.left):
                state.leftTrigger = .max
            case .trigger(.right):
                state.rightTrigger = .max
            case .dpad:
                state.buttons.formUnion(StickMath.dpadButtons(offset: offset, radius: frame.width / 2, deadZone: dpadDeadZone))
            case .stick(let side):
                let radius = frame.width * stickTravel
                let value = StickMath.stickValue(StickMath.vector(offset: offset, radius: radius, deadZone: stickDeadZone))
                if side == .left {
                    state.leftStick = value
                } else {
                    state.rightStick = value
                }
                sticks[element.id] = StickVisual(
                    baseOffset: CGVector(dx: contact.origin.x - frame.midX, dy: contact.origin.y - frame.midY),
                    knob: StickMath.vector(offset: offset, radius: radius, deadZone: 0)
                )
            }
        }

        self.state = state
        self.activeElements = active
        self.sticks = sticks
    }
}
