#if canImport(UIKit)
import CoreMotion
import SwiftUI
import UIKit
import VirtualControllerKit

@MainActor
@Observable
public final class ControllerModel {
    static let gridSize: CGFloat = 8
    /// Idle controls draw at this fraction of the layout opacity, so a press visibly lights up.
    static let idleOpacityFactor = 0.8
    private static let lastProfileKey = "lastProfile"
    private static let trackpadKey = "trackpadEnabled"

    public var layout: ControllerLayout
    public private(set) var input = TouchInputProcessor<ObjectIdentifier>()
    public private(set) var profileNames: [String] = []
    public private(set) var isEditing = false
    var selectedID: UUID?
    var snapToGrid = true
    /// Size of the area controls are laid out in, reported by the overlay.
    private(set) var canvasSize: CGSize = .zero
    /// Touches that miss every control drive the remote mouse like a trackpad.
    var isTrackpadEnabled: Bool {
        didSet { UserDefaults.standard.set(isTrackpadEnabled, forKey: Self.trackpadKey) }
    }

    /// Where gamepad state goes. Point this at a streaming client to drive a real session.
    @ObservationIgnored public weak var sink: GamepadSink?

    @ObservationIgnored private let store: LayoutStore
    @ObservationIgnored private var layoutBeforeEditing: ControllerLayout?
    /// The built-in layout, not yet saved. It's rebuilt to fit whenever the canvas size changes.
    @ObservationIgnored private var isUnsavedDefault: Bool
    @ObservationIgnored private var lastSentState = GamepadState()
    @ObservationIgnored private let haptics = UIImpactFeedbackGenerator(style: .light)
    @ObservationIgnored private var trackpad = TrackpadGestures<ObjectIdentifier>()
    @ObservationIgnored private var trackpadTouches = Set<ObjectIdentifier>()
    /// Sub-pixel motion and scroll carried over until it adds up to a whole unit.
    @ObservationIgnored private var pointerRemainder = CGVector.zero
    @ObservationIgnored private var scrollRemainder: CGFloat = 0
    @ObservationIgnored private let motionManager = CMMotionManager()
    @ObservationIgnored private var lastMotionTimestamp: TimeInterval?
    /// Right-stick deflection from the gyro, added to the touch stick.
    @ObservationIgnored private var gyroStick = StickValue.zero
    @ObservationIgnored private var gyroFrame = GyroFrame()
    @ObservationIgnored private var gyroSmoother = GyroSmoother()

    public init() {
        isTrackpadEnabled = UserDefaults.standard.object(forKey: Self.trackpadKey) as? Bool ?? true
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let store = LayoutStore(directory: support.appendingPathComponent("Layouts", isDirectory: true))
        let lastName = UserDefaults.standard.string(forKey: Self.lastProfileKey)
        let saved = lastName.flatMap { try? store.load(named: $0) }
        self.store = store
        self.layout = saved ?? .standard(in: .zero)
        self.isUnsavedDefault = saved == nil
        refreshProfiles()
    }

    func updateCanvasSize(_ size: CGSize) {
        canvasSize = size
        if isUnsavedDefault, !isEditing {
            layout = .standard(in: size)
        }
    }

    // MARK: - Playing

    func touchBegan(_ touch: ObjectIdentifier, at point: CGPoint) {
        let before = input.activeElements
        if input.began(touch, at: point, layout: layout, bounds: canvasSize) {
            inputChanged(pressedBefore: before)
        } else if isTrackpadEnabled {
            trackpadTouches.insert(touch)
            deliver(trackpad.began(touch, at: point, time: ProcessInfo.processInfo.systemUptime))
        }
    }

    func touchMoved(_ touch: ObjectIdentifier, to point: CGPoint) {
        if trackpadTouches.contains(touch) {
            deliver(trackpad.moved(touch, to: point, time: ProcessInfo.processInfo.systemUptime))
            return
        }
        let before = input.activeElements
        input.moved(touch, to: point, layout: layout, bounds: canvasSize)
        inputChanged(pressedBefore: before)
    }

    func touchEnded(_ touch: ObjectIdentifier) {
        if trackpadTouches.remove(touch) != nil {
            deliver(trackpad.ended(touch, time: ProcessInfo.processInfo.systemUptime))
            return
        }
        let before = input.activeElements
        input.ended(touch, layout: layout, bounds: canvasSize)
        inputChanged(pressedBefore: before)
    }

    /// Lets go of every held control and mouse button, e.g. when the controls are hidden
    /// mid-press.
    public func releaseAllTouches() {
        input.reset()
        inputChanged(pressedBefore: [])
        trackpadTouches.removeAll()
        deliver(trackpad.reset())
    }

    private func deliver(_ events: [TrackpadEvent]) {
        for event in events {
            switch event {
            case let .move(dx, dy):
                pointerRemainder.dx += dx
                pointerRemainder.dy += dy
                let whole = (x: Int(pointerRemainder.dx), y: Int(pointerRemainder.dy))
                pointerRemainder.dx -= CGFloat(whole.x)
                pointerRemainder.dy -= CGFloat(whole.y)
                if whole.x != 0 || whole.y != 0 {
                    sink?.movePointer(dx: whole.x, dy: whole.y)
                }
            case let .scroll(dy):
                scrollRemainder += dy
                let whole = Int(scrollRemainder)
                scrollRemainder -= CGFloat(whole)
                if whole != 0 {
                    sink?.scroll(by: whole)
                }
            case let .button(button, pressed):
                sink?.setMouseButton(button, pressed: pressed)
            }
        }
    }

    private func inputChanged(pressedBefore before: Set<UUID>) {
        if !input.activeElements.isSubset(of: before) {
            haptics.impactOccurred()
        }
        sendStateIfChanged()
    }

    /// Touch state plus any gyro deflection on the right stick.
    private var outputState: GamepadState {
        var state = input.state
        state.rightStick = state.rightStick.adding(gyroStick)
        return state
    }

    private func sendStateIfChanged() {
        let state = outputState
        if state != lastSentState {
            lastSentState = state
            sink?.send(state)
        }
    }

    // MARK: - Gyro

    /// Runs the gyro while playing with it enabled; the overlay calls this as that changes.
    func setGyroRunning(_ running: Bool) {
        if running {
            guard !motionManager.isDeviceMotionActive, motionManager.isDeviceMotionAvailable else { return }
            lastMotionTimestamp = nil
            // Relearn the screen's axes from how the phone is held now.
            gyroFrame.reset()
            gyroSmoother.reset()
            motionManager.deviceMotionUpdateInterval = 1.0 / 120
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let motion else { return }
                MainActor.assumeIsolated { self?.handleMotion(motion) }
            }
        } else if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
            gyroStick = .zero
            sendStateIfChanged()
        }
    }

    private func handleMotion(_ motion: CMDeviceMotion) {
        // Cap the step so a stalled frame doesn't arrive as one big jump.
        let interval = min(lastMotionTimestamp.map { motion.timestamp - $0 } ?? 0, 0.05)
        lastMotionTimestamp = motion.timestamp
        let settings = layout.gyro
        let rotation = motion.rotationRate
        let gravity = motion.gravity
        // Keep reading even while disengaged so the screen's axes are known when it engages.
        let raw = gyroFrame.screenRates(
            rotation: MotionVector(x: rotation.x, y: rotation.y, z: rotation.z),
            gravity: MotionVector(x: gravity.x, y: gravity.y, z: gravity.z)
        )
        guard settings.mode != .off, isGyroEngaged else {
            gyroSmoother.reset()
            if gyroStick != .zero {
                gyroStick = .zero
                sendStateIfChanged()
            }
            return
        }
        let rates = gyroSmoother.smooth(yaw: raw.yaw, pitch: raw.pitch)
        switch settings.mode {
        case .mouse:
            let delta = GyroAiming.mouseDelta(yaw: rates.yaw, pitch: rates.pitch, interval: interval, settings: settings)
            deliver([.move(dx: delta.dx, dy: delta.dy)])
        case .rightStick:
            gyroStick = GyroAiming.stickValue(yaw: rates.yaw, pitch: rates.pitch, settings: settings)
            sendStateIfChanged()
        case .off:
            break
        }
    }

    private var isGyroEngaged: Bool {
        switch layout.gyro.activation {
        case .always:
            true
        case .whileAiming:
            input.state.leftTrigger > 0
        case .whileTouchingRightStick:
            layout.elements.contains { $0.kind == .stick(.right) && input.activeElements.contains($0.id) }
        }
    }

    // MARK: - Editing

    public func beginEditing() {
        releaseAllTouches()
        layoutBeforeEditing = layout
        isEditing = true
    }

    public func finishEditing() {
        save()
        endEditing()
    }

    public func cancelEditing() {
        if let original = layoutBeforeEditing {
            layout = original
        }
        endEditing()
    }

    private func endEditing() {
        isEditing = false
        selectedID = nil
        layoutBeforeEditing = nil
    }

    func move(_ id: UUID, to point: CGPoint) {
        layout.move(id, to: point, in: canvasSize, grid: snapToGrid ? Self.gridSize : nil)
    }

    func resize(_ id: UUID, to scale: CGFloat) {
        layout.resize(id, to: scale, in: canvasSize)
    }

    func add(_ kind: ControlKind) {
        selectedID = layout.add(kind)
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        layout.remove(id)
        selectedID = nil
    }

    func resetToStandard() {
        let name = layout.name
        layout = .standard(in: canvasSize)
        layout.name = name
        selectedID = nil
    }

    // MARK: - Profiles

    public func switchProfile(to name: String) {
        guard name != layout.name, let loaded = try? store.load(named: name) else { return }
        layout = loaded
        isUnsavedDefault = false
        UserDefaults.standard.set(name, forKey: Self.lastProfileKey)
    }

    public func createProfile(named name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        layout.name = name
        save()
    }

    public func deleteCurrentProfile() {
        try? store.delete(named: layout.name)
        let next = store.names().first.flatMap { try? store.load(named: $0) }
        layout = next ?? .standard(in: canvasSize)
        isUnsavedDefault = next == nil
        UserDefaults.standard.set(layout.name, forKey: Self.lastProfileKey)
        refreshProfiles()
    }

    private func save() {
        do {
            try store.save(layout)
        } catch {
            print("Couldn't save layout \(layout.name): \(error)")
        }
        isUnsavedDefault = false
        UserDefaults.standard.set(layout.name, forKey: Self.lastProfileKey)
        refreshProfiles()
    }

    /// Saved profiles plus the current one, which may not have been saved yet.
    private func refreshProfiles() {
        profileNames = Set(store.names() + [layout.name])
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
#endif
