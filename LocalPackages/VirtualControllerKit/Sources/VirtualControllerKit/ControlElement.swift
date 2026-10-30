import CoreGraphics
import Foundation

public enum Side: String, Codable, Hashable, Sendable {
    case left, right
}

public enum ButtonID: String, Codable, Hashable, Sendable, CaseIterable {
    case a, b, x, y
    case leftShoulder, rightShoulder
    case back, start, guide
    case leftThumb, rightThumb

    public var gamepadButton: GamepadButtons {
        switch self {
        case .a: .a
        case .b: .b
        case .x: .x
        case .y: .y
        case .leftShoulder: .leftShoulder
        case .rightShoulder: .rightShoulder
        case .back: .back
        case .start: .start
        case .guide: .guide
        case .leftThumb: .leftThumb
        case .rightThumb: .rightThumb
        }
    }

    /// Text drawn on the control.
    public var label: String {
        switch self {
        case .a: "A"
        case .b: "B"
        case .x: "X"
        case .y: "Y"
        case .leftShoulder: "LB"
        case .rightShoulder: "RB"
        case .back: "View"
        case .start: "Menu"
        case .guide: "Home"
        case .leftThumb: "L3"
        case .rightThumb: "R3"
        }
    }
}

public enum ControlKind: Codable, Hashable, Sendable {
    case button(ButtonID)
    case trigger(Side)
    case stick(Side)
    case dpad

    public var displayName: String {
        switch self {
        case .button(let id):
            switch id {
            case .a, .b, .x, .y: "\(id.label) button"
            case .leftShoulder: "Left bumper"
            case .rightShoulder: "Right bumper"
            case .back: "View button"
            case .start: "Menu button"
            case .guide: "Home button"
            case .leftThumb: "Left stick click"
            case .rightThumb: "Right stick click"
            }
        case .trigger(.left): "Left trigger"
        case .trigger(.right): "Right trigger"
        case .stick(.left): "Left stick"
        case .stick(.right): "Right stick"
        case .dpad: "D-pad"
        }
    }

    /// Size in points at scale 1. Sizes stay in points (not screen fractions) so a control
    /// keeps the same thumb-sized footprint on every device.
    public var baseSize: CGSize {
        switch self {
        case .button(.a), .button(.b), .button(.x), .button(.y):
            CGSize(width: 56, height: 56)
        case .button(.leftShoulder), .button(.rightShoulder):
            CGSize(width: 76, height: 40)
        case .button:
            CGSize(width: 44, height: 44)
        case .trigger:
            CGSize(width: 76, height: 44)
        case .stick, .dpad:
            CGSize(width: 136, height: 136)
        }
    }
}

extension ControlKind: CaseIterable {
    public static var allCases: [ControlKind] {
        ButtonID.allCases.map(ControlKind.button)
            + [.trigger(.left), .trigger(.right), .stick(.left), .stick(.right), .dpad]
    }
}

public struct ControlElement: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ControlKind
    /// Center as a fraction of the overlay's size (0...1 on each axis), so a layout carries
    /// across screen sizes.
    public var center: CGPoint
    public var scale: CGFloat

    public init(id: UUID = UUID(), kind: ControlKind, center: CGPoint, scale: CGFloat = 1) {
        self.id = id
        self.kind = kind
        self.center = center
        self.scale = scale
    }

    public var size: CGSize {
        CGSize(width: kind.baseSize.width * scale, height: kind.baseSize.height * scale)
    }

    /// Frame in overlay coordinates, shifted if needed so the control stays fully on screen.
    public func frame(in bounds: CGSize) -> CGRect {
        let width = min(size.width, bounds.width)
        let height = min(size.height, bounds.height)
        let x = (center.x * bounds.width - width / 2).clamped(to: 0...(bounds.width - width))
        let y = (center.y * bounds.height - height / 2).clamped(to: 0...(bounds.height - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
