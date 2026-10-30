/// Button bitmask using XInput's XINPUT_GAMEPAD values, the layout GeForce NOW-style
/// clients send for a gamepad.
public struct GamepadButtons: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let dpadUp = GamepadButtons(rawValue: 0x0001)
    public static let dpadDown = GamepadButtons(rawValue: 0x0002)
    public static let dpadLeft = GamepadButtons(rawValue: 0x0004)
    public static let dpadRight = GamepadButtons(rawValue: 0x0008)
    public static let start = GamepadButtons(rawValue: 0x0010)
    public static let back = GamepadButtons(rawValue: 0x0020)
    public static let leftThumb = GamepadButtons(rawValue: 0x0040)
    public static let rightThumb = GamepadButtons(rawValue: 0x0080)
    public static let leftShoulder = GamepadButtons(rawValue: 0x0100)
    public static let rightShoulder = GamepadButtons(rawValue: 0x0200)
    public static let guide = GamepadButtons(rawValue: 0x0400)
    public static let a = GamepadButtons(rawValue: 0x1000)
    public static let b = GamepadButtons(rawValue: 0x2000)
    public static let x = GamepadButtons(rawValue: 0x4000)
    public static let y = GamepadButtons(rawValue: 0x8000)

    private static let named: [(GamepadButtons, String)] = [
        (.a, "A"), (.b, "B"), (.x, "X"), (.y, "Y"),
        (.leftShoulder, "LB"), (.rightShoulder, "RB"),
        (.back, "View"), (.start, "Menu"), (.guide, "Home"),
        (.leftThumb, "L3"), (.rightThumb, "R3"),
        (.dpadUp, "Up"), (.dpadDown, "Down"), (.dpadLeft, "Left"), (.dpadRight, "Right"),
    ]

    /// Short names of the held buttons, for debug readouts.
    public var names: [String] {
        Self.named.filter { contains($0.0) }.map(\.1)
    }
}

/// Thumbstick position in XInput's range: -32768...32767, with y positive pointing up.
public struct StickValue: Hashable, Sendable {
    public var x: Int16
    public var y: Int16

    public init(x: Int16, y: Int16) {
        self.x = x
        self.y = y
    }

    public static let zero = StickValue(x: 0, y: 0)
}

/// One snapshot of the virtual pad, shaped like XINPUT_GAMEPAD.
public struct GamepadState: Hashable, Sendable {
    public var buttons: GamepadButtons = []
    public var leftTrigger: UInt8 = 0
    public var rightTrigger: UInt8 = 0
    public var leftStick: StickValue = .zero
    public var rightStick: StickValue = .zero

    public init() {}
}

/// Receives the pad's state whenever it changes. A streaming client implements this to
/// forward input to the remote session as a gamepad packet. Called on the main actor, where
/// touches arrive.
@MainActor
public protocol GamepadSink: AnyObject {
    func send(_ state: GamepadState)
    /// Relative pointer motion in remote pixels, from the touch trackpad.
    func movePointer(dx: Int, dy: Int)
    /// Wheel motion; negative scrolls content down.
    func scroll(by delta: Int)
    func setMouseButton(_ button: MouseButton, pressed: Bool)
}

/// Gamepad-only sinks can ignore the trackpad.
public extension GamepadSink {
    func movePointer(dx: Int, dy: Int) {}
    func scroll(by delta: Int) {}
    func setMouseButton(_ button: MouseButton, pressed: Bool) {}
}
