import SwiftUI
import VirtualControllerKit
import VirtualControllerUI

/// On-screen gamepad over the stream. The touch pad drives GFN input as an extra controller,
/// and a pause button stands in for the Siri Remote's Menu button.
struct StreamTouchControls: View {
    let streamController: GFNStreamController
    let onPause: () -> Void

    @State private var model = ControllerModel()
    // ControllerModel holds its sink weakly.
    @State private var bridge: TouchGamepadBridge?
    @State private var isKeyboardActive = false

    var body: some View {
        ZStack {
            StreamKeyboard(isActive: $isKeyboardActive, streamController: streamController)
                .frame(width: 0, height: 0)

            ControllerOverlay(model: model)

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
            streamController.setVirtualGamepad(VirtualGamepadState(GamepadState()))
        }
        .onDisappear {
            // Stay connected while hidden behind the pause menu, but let go of everything.
            model.releaseAllTouches()
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
