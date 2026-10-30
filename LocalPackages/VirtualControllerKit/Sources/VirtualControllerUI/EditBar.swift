#if canImport(UIKit)
import SwiftUI
import VirtualControllerKit

/// Floating toolbar shown while editing the layout.
public struct EditBar: View {
    @Bindable var model: ControllerModel
    @State private var atTop = true
    @State private var showsGyroSettings = false

    public init(model: ControllerModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                Menu {
                    ForEach(ControlKind.allCases, id: \.self) { kind in
                        Button(kind.displayName) { model.add(kind) }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .accessibilityLabel("Add control")

                Toggle(isOn: $model.snapToGrid) { Image(systemName: "grid") }
                    .accessibilityLabel("Snap to grid")
                Toggle(isOn: $model.layout.floatingSticks) { Image(systemName: "scope") }
                    .accessibilityLabel("Floating sticks")

                Button("Gyro", systemImage: "gyroscope") { showsGyroSettings = true }
                    .tint(model.layout.gyro.mode == .off ? nil : .green)
                    .popover(isPresented: $showsGyroSettings) {
                        GyroSettingsPanel(settings: $model.layout.gyro)
                            .presentationCompactAdaptation(.popover)
                    }

                Button("Reset", systemImage: "arrow.counterclockwise") { model.resetToStandard() }
                    .labelStyle(.iconOnly)
                Button("Move toolbar", systemImage: atTop ? "arrow.down.to.line" : "arrow.up.to.line") {
                    atTop.toggle()
                }
                .labelStyle(.iconOnly)

                Divider().frame(height: 20)
                Button("Cancel") { model.cancelEditing() }
                Button("Done") { model.finishEditing() }.bold()
            }
            .toggleStyle(.button)

            HStack(spacing: 10) {
                Label("Opacity", systemImage: "circle.lefthalf.filled")
                Slider(value: $model.layout.opacity, in: 0.2...1)
                    .frame(width: 140)
                Text(model.layout.opacity, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
                Divider().frame(height: 20)
                Toggle(isOn: $model.isTrackpadEnabled) {
                    Label("Touch mouse", systemImage: "cursorarrow.motionlines")
                }
                .fixedSize()
            }

            if let id = model.selectedID, let element = model.layout[id] {
                HStack(spacing: 10) {
                    Text(element.kind.displayName)
                        .frame(width: 130, alignment: .leading)
                    Image(systemName: "minus.magnifyingglass")
                    Slider(
                        value: Binding(get: { element.scale }, set: { model.resize(id, to: $0) }),
                        in: ControllerLayout.scaleRange
                    )
                    .frame(width: 160)
                    Image(systemName: "plus.magnifyingglass")
                    Button("Delete", systemImage: "trash", role: .destructive) { model.deleteSelected() }
                        .labelStyle(.iconOnly)
                }
            }
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .frame(maxHeight: .infinity, alignment: atTop ? .top : .bottom)
        .padding(.vertical, 4)
    }
}
#endif
