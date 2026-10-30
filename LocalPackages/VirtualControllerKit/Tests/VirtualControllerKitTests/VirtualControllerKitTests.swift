import CoreGraphics
import Foundation
import Testing
@testable import VirtualControllerKit

private let bounds = CGSize(width: 800, height: 400)

private func layout(_ elements: ControlElement...) -> ControllerLayout {
    ControllerLayout(name: "Test", elements: elements)
}

// MARK: - Layout editing

@Test func moveConvertsToFractionsAndSnaps() {
    let button = ControlElement(kind: .button(.a), center: CGPoint(x: 0.5, y: 0.5))
    var layout = layout(button)
    layout.move(button.id, to: CGPoint(x: 203, y: 99), in: bounds, grid: 8)
    #expect(layout[button.id]?.center == CGPoint(x: 200.0 / 800, y: 96.0 / 400))
}

@Test func moveKeepsControlOnScreen() {
    let stick = ControlElement(kind: .stick(.left), center: CGPoint(x: 0.5, y: 0.5))
    var layout = layout(stick)
    layout.move(stick.id, to: CGPoint(x: -500, y: 10_000), in: bounds)
    let frame = layout[stick.id]!.frame(in: bounds)
    #expect(frame.minX == 0)
    #expect(frame.maxY == bounds.height)
}

@Test func resizeClampsScaleAndPushesBackOnScreen() {
    let button = ControlElement(kind: .button(.a), center: CGPoint(x: 1, y: 1))
    var layout = layout(button)
    layout.resize(button.id, to: 10, in: bounds)
    #expect(layout[button.id]?.scale == ControllerLayout.scaleRange.upperBound)
    let frame = layout[button.id]!.frame(in: bounds)
    #expect(frame.maxX == bounds.width)
    #expect(frame.maxY == bounds.height)

    layout.resize(button.id, to: 0, in: bounds)
    #expect(layout[button.id]?.scale == ControllerLayout.scaleRange.lowerBound)
}

@Test func hitTestPrefersNearestCenter() {
    let left = ControlElement(kind: .button(.x), center: CGPoint(x: 100.0 / 800, y: 0.5))
    let right = ControlElement(kind: .button(.b), center: CGPoint(x: 150.0 / 800, y: 0.5))
    let layout = layout(left, right)
    // Both padded hit areas cover x = 130; B's center is closer.
    #expect(layout.element(at: CGPoint(x: 130, y: 200), in: bounds)?.id == right.id)
    #expect(layout.element(at: CGPoint(x: 115, y: 200), in: bounds)?.id == left.id)
    #expect(layout.element(at: CGPoint(x: 600, y: 200), in: bounds) == nil)
}

@Test(arguments: [
    CGSize(width: 667, height: 375),   // small phone, landscape
    CGSize(width: 734, height: 372),   // notched phone, landscape safe area
    CGSize(width: 678, height: 466),   // squarish foldable
    CGSize(width: 1194, height: 790),  // iPad
])
func standardLayoutFitsWithoutOverlaps(size: CGSize) {
    let frames = ControllerLayout.standard(in: size).elements.map { ($0.kind.displayName, $0.frame(in: size)) }
    for (name, frame) in frames {
        #expect(CGRect(origin: .zero, size: size).contains(frame), "\(name) is off screen")
    }
    for i in frames.indices {
        for j in frames.indices where j > i {
            #expect(!frames[i].1.intersects(frames[j].1), "\(frames[i].0) overlaps \(frames[j].0)")
        }
    }
}

@Test func layoutRoundTripsThroughJSON() throws {
    let original = ControllerLayout.standard(in: bounds)
    let decoded = try JSONDecoder().decode(ControllerLayout.self, from: JSONEncoder().encode(original))
    #expect(decoded == original)
}

// MARK: - Stick and D-pad math

@Test func stickDeadZoneAndRange() {
    #expect(StickMath.vector(offset: CGVector(dx: 5, dy: 0), radius: 100, deadZone: 0.1) == .zero)
    #expect(StickMath.stickValue(StickMath.vector(offset: CGVector(dx: 500, dy: 0), radius: 100, deadZone: 0.1)) == StickValue(x: 32767, y: 0))
    // Dragging up on screen pushes the stick up (positive y).
    #expect(StickMath.stickValue(StickMath.vector(offset: CGVector(dx: 0, dy: -100), radius: 100, deadZone: 0)) == StickValue(x: 0, y: 32767))
    // Just past the dead zone the output starts near zero instead of jumping.
    let justPast = StickMath.vector(offset: CGVector(dx: 11, dy: 0), radius: 100, deadZone: 0.1)
    #expect(justPast.dx > 0 && justPast.dx < 0.02)
}

@Test func dpadEightWay() {
    #expect(StickMath.dpadButtons(offset: CGVector(dx: 0, dy: -50), radius: 60, deadZone: 0.25) == .dpadUp)
    #expect(StickMath.dpadButtons(offset: CGVector(dx: 40, dy: 40), radius: 60, deadZone: 0.25) == [.dpadDown, .dpadRight])
    #expect(StickMath.dpadButtons(offset: CGVector(dx: -50, dy: 3), radius: 60, deadZone: 0.25) == .dpadLeft)
    #expect(StickMath.dpadButtons(offset: CGVector(dx: 2, dy: 2), radius: 60, deadZone: 0.25) == [])
}

// MARK: - Touch processing

@Test func pressAndReleaseButton() {
    let a = ControlElement(kind: .button(.a), center: CGPoint(x: 0.5, y: 0.5))
    let layout = layout(a)
    var input = TouchInputProcessor<Int>()
    input.began(1, at: CGPoint(x: 400, y: 200), layout: layout, bounds: bounds)
    #expect(input.state.buttons == .a)
    #expect(input.activeElements == [a.id])
    input.ended(1, layout: layout, bounds: bounds)
    #expect(input.state == GamepadState())
}

@Test func secondFingerKeepsButtonHeld() {
    let a = ControlElement(kind: .button(.a), center: CGPoint(x: 0.5, y: 0.5))
    let layout = layout(a)
    var input = TouchInputProcessor<Int>()
    input.began(1, at: CGPoint(x: 400, y: 200), layout: layout, bounds: bounds)
    input.began(2, at: CGPoint(x: 405, y: 205), layout: layout, bounds: bounds)
    input.ended(1, layout: layout, bounds: bounds)
    #expect(input.state.buttons == .a)
}

@Test func touchOutsideControlsIsIgnored() {
    let a = ControlElement(kind: .button(.a), center: CGPoint(x: 0.5, y: 0.5))
    var input = TouchInputProcessor<Int>()
    input.began(1, at: CGPoint(x: 10, y: 10), layout: layout(a), bounds: bounds)
    #expect(input.activeElements.isEmpty)
}

@Test func slidingAcrossButtonsRollsThePress() {
    let x = ControlElement(kind: .button(.x), center: CGPoint(x: 0.5, y: 0.5))
    let b = ControlElement(kind: .button(.b), center: CGPoint(x: 0.7, y: 0.5))
    let layout = layout(x, b)
    var input = TouchInputProcessor<Int>()
    input.began(1, at: CGPoint(x: 400, y: 200), layout: layout, bounds: bounds)
    input.moved(1, to: CGPoint(x: 560, y: 200), layout: layout, bounds: bounds)
    #expect(input.state.buttons == .b)
}

@Test func buttonsCombineWithSticksAndTriggers() {
    let stick = ControlElement(kind: .stick(.left), center: CGPoint(x: 0.2, y: 0.5))
    let trigger = ControlElement(kind: .trigger(.right), center: CGPoint(x: 0.9, y: 0.1))
    let a = ControlElement(kind: .button(.a), center: CGPoint(x: 0.9, y: 0.7))
    let layout = layout(stick, trigger, a)
    var input = TouchInputProcessor<Int>()
    input.began(1, at: CGPoint(x: 160, y: 200), layout: layout, bounds: bounds)
    input.moved(1, to: CGPoint(x: 260, y: 200), layout: layout, bounds: bounds)
    input.began(2, at: CGPoint(x: 720, y: 40), layout: layout, bounds: bounds)
    input.began(3, at: CGPoint(x: 720, y: 280), layout: layout, bounds: bounds)
    #expect(input.state.leftStick == StickValue(x: 32767, y: 0))
    #expect(input.state.rightTrigger == 255)
    #expect(input.state.buttons == .a)
    #expect(input.sticks[stick.id]?.knob == CGVector(dx: 1, dy: 0))
}

@Test func floatingStickCentersOnFirstTouch() {
    let stick = ControlElement(kind: .stick(.right), center: CGPoint(x: 0.5, y: 0.5))
    var layout = layout(stick)
    layout.floatingSticks = true
    var input = TouchInputProcessor<Int>()
    // Landing off-center gives no deflection when floating...
    input.began(1, at: CGPoint(x: 440, y: 230), layout: layout, bounds: bounds)
    #expect(input.state.rightStick == .zero)
    #expect(input.sticks[stick.id]?.baseOffset == CGVector(dx: 40, dy: 30))

    // ...but deflects from the control's center when fixed.
    layout.floatingSticks = false
    input.reset()
    input.began(1, at: CGPoint(x: 440, y: 230), layout: layout, bounds: bounds)
    #expect(input.state.rightStick.x > 0)
    #expect(input.state.rightStick.y < 0)
}

// MARK: - Storage

@Test func storeSavesListsAndDeletes() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LayoutStore(directory: directory)

    var racing = ControllerLayout.standard(in: bounds)
    racing.name = "Racing / Forza"
    try store.save(racing)
    try store.save(.standard(in: bounds))

    #expect(store.names() == ["Default", "Racing / Forza"])
    #expect(try store.load(named: "Racing / Forza") == racing)

    try store.delete(named: "Default")
    #expect(store.names() == ["Racing / Forza"])
}

// MARK: - Trackpad

@Test func touchOffControlsIsNotClaimed() {
    let a = ControlElement(kind: .button(.a), center: CGPoint(x: 0.5, y: 0.5))
    var input = TouchInputProcessor<Int>()
    #expect(input.began(1, at: CGPoint(x: 10, y: 10), layout: layout(a), bounds: bounds) == false)
    #expect(input.began(2, at: CGPoint(x: 400, y: 200), layout: layout(a), bounds: bounds) == true)
}

@Test func dragMovesPointerScaledBySpeed() {
    var pad = TrackpadGestures<Int>()
    pad.pointerSpeed = 2
    #expect(pad.began(1, at: CGPoint(x: 100, y: 100), time: 0).isEmpty)
    #expect(pad.moved(1, to: CGPoint(x: 110, y: 95), time: 0.05) == [.move(dx: 20, dy: -10)])
    // Moved too far to count as a tap.
    #expect(pad.ended(1, time: 0.1).isEmpty)
}

@Test func tapClicksAndTwoFingerTapRightClicks() {
    var pad = TrackpadGestures<Int>()
    _ = pad.began(1, at: CGPoint(x: 100, y: 100), time: 0)
    #expect(pad.ended(1, time: 0.1) == [.button(.left, pressed: true), .button(.left, pressed: false)])

    _ = pad.began(1, at: CGPoint(x: 100, y: 100), time: 5)
    _ = pad.began(2, at: CGPoint(x: 140, y: 100), time: 5.02)
    #expect(pad.ended(1, time: 5.1).isEmpty)
    #expect(pad.ended(2, time: 5.12) == [.button(.right, pressed: true), .button(.right, pressed: false)])
}

@Test func slowPressIsNotATap() {
    var pad = TrackpadGestures<Int>()
    _ = pad.began(1, at: CGPoint(x: 100, y: 100), time: 0)
    #expect(pad.ended(1, time: 1).isEmpty)
}

@Test func tapThenTouchHoldsLeftButtonForDragging() {
    var pad = TrackpadGestures<Int>()
    _ = pad.began(1, at: CGPoint(x: 100, y: 100), time: 0)
    _ = pad.ended(1, time: 0.1)
    #expect(pad.began(2, at: CGPoint(x: 100, y: 100), time: 0.25) == [.button(.left, pressed: true)])
    #expect(pad.moved(2, to: CGPoint(x: 150, y: 100), time: 0.4) == [.move(dx: 125, dy: 0)])
    #expect(pad.ended(2, time: 0.6) == [.button(.left, pressed: false)])
    // A later touch after the window is a fresh gesture.
    #expect(pad.began(3, at: CGPoint(x: 100, y: 100), time: 2).isEmpty)
}

@Test func twoFingerDragScrolls() {
    var pad = TrackpadGestures<Int>()
    pad.scrollSpeed = 4
    _ = pad.began(1, at: CGPoint(x: 100, y: 100), time: 0)
    _ = pad.began(2, at: CGPoint(x: 140, y: 100), time: 0)
    // Fingers pushing content up scroll it down: negative wheel.
    #expect(pad.moved(1, to: CGPoint(x: 100, y: 90), time: 0.05) == [.scroll(dy: -20)])
}

@Test func resetReleasesAHeldDrag() {
    var pad = TrackpadGestures<Int>()
    _ = pad.began(1, at: .zero, time: 0)
    _ = pad.ended(1, time: 0.1)
    _ = pad.began(2, at: .zero, time: 0.2)
    #expect(pad.reset() == [.button(.left, pressed: false)])
    #expect(pad.reset().isEmpty)
}

// MARK: - Gyro

@Test func layoutsSavedBeforeGyroStillLoad() throws {
    let legacy = #"{"name":"Old","elements":[],"opacity":0.8,"floatingSticks":false}"#
    let decoded = try JSONDecoder().decode(ControllerLayout.self, from: Data(legacy.utf8))
    #expect(decoded.gyro == GyroSettings())
    #expect(decoded.gyro.mode == .off)

    var layout = decoded
    layout.gyro.mode = .mouse
    let roundTripped = try JSONDecoder().decode(ControllerLayout.self, from: JSONEncoder().encode(layout))
    #expect(roundTripped.gyro.mode == .mouse)
}

/// Builds a sensor reading for a phone whose screen axes point along `right`, `up` and
/// `outOfScreen` in the sensor frame, tilted back by `tilt` radians toward the player.
private func reading(
    right: MotionVector, up: MotionVector, outOfScreen: MotionVector, tilt: Double,
    turnRight: Double = 0, lookUp: Double = 0
) -> (rotation: MotionVector, gravity: MotionVector) {
    func add(_ a: MotionVector, _ b: MotionVector) -> MotionVector { MotionVector(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
    // World up leans from the screen's up toward the player as the phone tilts back.
    let worldUp = add(up.scaled(cos(tilt)), outOfScreen.scaled(sin(tilt)))
    // Turning right is a negative rotation about world up; looking up a positive one about right.
    let rotation = add(worldUp.scaled(-turnRight), right.scaled(lookUp))
    return (rotation, worldUp.scaled(-1))
}

@Test(arguments: [
    // Standard iPhone in landscape: screen right = sensor -y, up = +x, facing +z.
    (MotionVector(x: 0, y: -1, z: 0), MotionVector(x: 1, y: 0, z: 0), MotionVector(x: 0, y: 0, z: 1)),
    // Sensor rotated 90° against the screen, as a foldable's inner display can be.
    (MotionVector(x: 1, y: 0, z: 0), MotionVector(x: 0, y: 1, z: 0), MotionVector(x: 0, y: 0, z: 1)),
    // Sensor facing the other way (z out of the back).
    (MotionVector(x: 1, y: 0, z: 0), MotionVector(x: 0, y: -1, z: 0), MotionVector(x: 0, y: 0, z: -1)),
])
func gyroFollowsTheScreenHoweverTheSensorIsMounted(axes: (MotionVector, MotionVector, MotionVector)) {
    let (right, up, out) = axes
    var frame = GyroFrame()
    let rate = Double.pi / 2 // 90°/s
    for tilt in [0.35, 0.8, 1.25] { // held a little back, well back, and nearly flat
        let turning = reading(right: right, up: up, outOfScreen: out, tilt: tilt, turnRight: rate)
        let turned = frame.screenRates(rotation: turning.rotation, gravity: turning.gravity)
        #expect(abs(turned.yaw - 90) < 0.01, "turning right, tilt \(tilt)")
        #expect(abs(turned.pitch) < 0.01)

        let tilting = reading(right: right, up: up, outOfScreen: out, tilt: tilt, lookUp: rate)
        let tilted = frame.screenRates(rotation: tilting.rotation, gravity: tilting.gravity)
        #expect(abs(tilted.pitch - 90) < 0.01, "looking up, tilt \(tilt)")
        #expect(abs(tilted.yaw) < 0.01)
    }
}

@Test func gyroIgnoresMissingGravity() {
    var frame = GyroFrame()
    let rates = frame.screenRates(rotation: MotionVector(x: 1, y: 1, z: 1), gravity: MotionVector(x: 0, y: 0, z: 0))
    #expect(rates.yaw == 0 && rates.pitch == 0)
}

@Test func gyroMouseScalesAndInverts() {
    var settings = GyroSettings()
    settings.mode = .mouse
    settings.sensitivity = 2
    // 10°/s right and up for 0.1 s = 1° each way; 8 px/° × 2 = 16 px.
    let delta = GyroAiming.mouseDelta(yaw: 10, pitch: 10, interval: 0.1, settings: settings)
    #expect(abs(delta.dx - 16) < 0.001 && abs(delta.dy + 16) < 0.001)

    settings.invertVertical = true
    #expect(GyroAiming.mouseDelta(yaw: 0, pitch: 10, interval: 0.1, settings: settings).dy > 0)
}

@Test func gyroStickClampsAndClearsGameDeadZones() {
    let settings = GyroSettings()
    #expect(GyroAiming.stickValue(yaw: 1000, pitch: 0, settings: settings).x == 32767)
    #expect(GyroAiming.stickValue(yaw: 0, pitch: 0, settings: settings) == .zero)
    // A resting hand doesn't drift the camera.
    #expect(GyroAiming.stickValue(yaw: 0.4, pitch: -0.4, settings: settings) == .zero)
    // A slow turn still produces at least the dead-zone compensation.
    let slow = GyroAiming.stickValue(yaw: 2, pitch: 0, settings: settings)
    #expect(slow.x > Int16(32767 * 0.12))
    // Looking up is positive y on the stick.
    #expect(GyroAiming.stickValue(yaw: 0, pitch: 90, settings: settings).y > 0)
    #expect(StickValue(x: 30000, y: 0).adding(StickValue(x: 10000, y: 0)).x == 32767)
}

@Test(arguments: [0.3, 1.0])
func tiltingUpAndBackReturnsToTheSameSpot(startTilt: Double) {
    // Landscape iPhone axes; the phone tilts up by 0.4 rad over 0.5 s, then back over 1 s,
    // with gravity following the real orientation the whole way.
    let right = MotionVector(x: 0, y: -1, z: 0), up = MotionVector(x: 1, y: 0, z: 0), out = MotionVector(x: 0, y: 0, z: 1)
    var frame = GyroFrame()
    var smoother = GyroSmoother()
    var settings = GyroSettings()
    settings.mode = .mouse
    let dt = 1.0 / 120
    var tilt = startTilt
    var pointer = CGVector.zero
    func step(lookUp: Double) {
        let sample = reading(right: right, up: up, outOfScreen: out, tilt: tilt, lookUp: lookUp)
        let raw = frame.screenRates(rotation: sample.rotation, gravity: sample.gravity)
        let rates = smoother.smooth(yaw: raw.yaw, pitch: raw.pitch)
        let delta = GyroAiming.mouseDelta(yaw: rates.yaw, pitch: rates.pitch, interval: dt, settings: settings)
        pointer.dx += delta.dx
        pointer.dy += delta.dy
        tilt -= lookUp * dt // looking up tips the screen back toward vertical
    }
    for _ in 0 ..< 60 { step(lookUp: 0.8) }      // fast up
    for _ in 0 ..< 120 { step(lookUp: -0.4) }    // slower down
    for _ in 0 ..< GyroSmoother.windowLength { step(lookUp: 0) } // let the window drain
    #expect(abs(pointer.dy) < 0.5, "ended \(pointer.dy) px from the start")
    #expect(abs(pointer.dx) < 0.5)
}

@Test func smoothingKeepsSlowMotion() {
    var smoother = GyroSmoother()
    var total: CGFloat = 0
    for _ in 0 ..< 100 { total += smoother.smooth(yaw: 1, pitch: 0).yaw } // 1°/s: fully smoothed
    for _ in 0 ..< GyroSmoother.windowLength { total += smoother.smooth(yaw: 0, pitch: 0).yaw }
    #expect(abs(total - 100) < 0.001)
}
