#if canImport(UIKit)
import SwiftUI
import VirtualControllerKit

/// Steam Input-style gyro options for the current layout.
struct GyroSettingsPanel: View {
    @Binding var settings: GyroSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Gyro Aiming", systemImage: "gyroscope")
                .font(.headline)

            Picker("Output", selection: $settings.mode) {
                Text("Off").tag(GyroOutputMode.off)
                Text("Mouse").tag(GyroOutputMode.mouse)
                Text("Right Stick").tag(GyroOutputMode.rightStick)
            }
            .pickerStyle(.segmented)

            if settings.mode != .off {
                LabeledContent("Active") {
                    Picker("Active", selection: $settings.activation) {
                        Text("Always").tag(GyroActivation.always)
                        Text("While Aiming (LT held)").tag(GyroActivation.whileAiming)
                        Text("While Touching Right Stick").tag(GyroActivation.whileTouchingRightStick)
                    }
                    .pickerStyle(.menu)
                }

                LabeledContent("Sensitivity") {
                    HStack {
                        Slider(value: $settings.sensitivity, in: GyroSettings.sensitivityRange)
                        Text(settings.sensitivity, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                Toggle("Invert Horizontal", isOn: $settings.invertHorizontal)
                Toggle("Invert Vertical", isOn: $settings.invertVertical)

                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 360)
    }

    private var hint: String {
        switch settings.mode {
        case .mouse:
            "Turn the phone to move the pointer, like a mouse."
        case .rightStick:
            "Turn the phone to look around; it adds to your thumb on the right stick."
        case .off:
            ""
        }
    }
}
#endif
