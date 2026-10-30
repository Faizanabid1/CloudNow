import GameController
import SwiftUI
import VirtualControllerKit
import VirtualControllerUI

/// On-screen gamepad over the stream. The touch pad drives GFN input as an extra controller,
/// and a pause button stands in for the Siri Remote's Menu button. The pad hides itself while
/// a physical controller is connected, unless the player asks for it.
struct StreamTouchControls: View {
    let streamController: GFNStreamController
    let onPause: () -> Void

    @State private var model = ControllerModel()
    // ControllerModel holds its sink weakly.
    @State private var bridge: TouchGamepadBridge?
    @State private var isKeyboardActive = false
    @State private var hasPhysicalController = Self.physicalControllerConnected
    /// nil follows the controller connection; true or false is the player's own choice.
    @State private var touchControlsOverride: Bool?

    private var showsTouchControls: Bool {
        touchControlsOverride ?? !hasPhysicalController
    }

    private static var physicalControllerConnected: Bool {
        GCController.controllers().contains { $0.extendedGamepad != nil }
    }

    var body: some View {
        ZStack {
            StreamKeyboard(isActive: $isKeyboardActive, streamController: streamController)
                .frame(width: 0, height: 0)

            if showsTouchControls || model.isEditing {
                ControllerOverlay(model: model)
            }

            if model.isEditing {
                EditBar(model: model)
            } else {
                controlBar
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 70)
            }
        }
        .onAppear {
            let bridge = TouchGamepadBridge(streamController: streamController)
            self.bridge = bridge
            model.sink = bridge
            // Connect the pad right away so the game sees a controller before the first touch.
            if showsTouchControls {
                streamController.setVirtualGamepad(VirtualGamepadState(GamepadState()))
            }
        }
        .onDisappear {
            // Stay connected while hidden behind the pause menu, but let go of everything.
            model.releaseAllTouches()
        }
        .onChange(of: showsTouchControls) { _, shows in
            if shows {
                streamController.setVirtualGamepad(VirtualGamepadState(GamepadState()))
            } else {
                // Unplug the touch pad so the game only sees the real controller.
                model.releaseAllTouches()
                streamController.setVirtualGamepad(nil)
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .GCControllerDidConnect) {
                hasPhysicalController = Self.physicalControllerConnected
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .GCControllerDidDisconnect) {
                hasPhysicalController = Self.physicalControllerConnected
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 18) {
            Button("Pause", systemImage: "pause.fill", action: onPause)
            Button(
                isKeyboardActive ? "Hide Keyboard" : "Keyboard",
                systemImage: isKeyboardActive ? "keyboard.chevron.compact.down" : "keyboard"
            ) {
                isKeyboardActive.toggle()
            }
            Button(
                showsTouchControls ? "Hide Touch Controls" : "Show Touch Controls",
                systemImage: showsTouchControls ? "gamecontroller.fill" : "gamecontroller"
            ) {
                touchControlsOverride = !showsTouchControls
            }
            Button("Edit Controls", systemImage: "slider.horizontal.3") {
                isKeyboardActive = false
                model.beginEditing()
            }
        }
        .labelStyle(.iconOnly)
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private final class TouchGamepadBridge: GamepadSink {
    private weak var streamController: GFNStreamController?

    init(streamController: GFNStreamController) {
        self.streamController = streamController
    }

    func send(_ state: GamepadState) {
        streamController?.setVirtualGamepad(VirtualGamepadState(state))
    }

    func movePointer(dx: Int, dy: Int) {
        streamController?.moveMouse(dx: Int16(clamping: dx), dy: Int16(clamping: dy))
    }

    func scroll(by delta: Int) {
        streamController?.scrollMouse(by: Int16(clamping: delta))
    }

    func setMouseButton(_ button: MouseButton, pressed: Bool) {
        let gfnButton: UInt8 = switch button {
        case .left: 1
        case .middle: 2
        case .right: 3
        }
        streamController?.setMouseButton(gfnButton, down: pressed)
    }
}

private extension VirtualGamepadState {
    nonisolated init(_ state: GamepadState) {
        self.init(
            buttons: state.buttons.rawValue,
            leftTrigger: state.leftTrigger,
            rightTrigger: state.rightTrigger,
            leftStickX: state.leftStick.x,
            leftStickY: state.leftStick.y,
            rightStickX: state.rightStick.x,
            rightStickY: state.rightStick.y
        )
    }
}
