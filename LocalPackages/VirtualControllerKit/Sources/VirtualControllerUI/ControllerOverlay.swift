#if canImport(UIKit)
import SwiftUI
import UIKit
import VirtualControllerKit

/// Draws the controls and routes touches: raw multi-touch while playing, SwiftUI gestures
/// while editing.
public struct ControllerOverlay: View {
    let model: ControllerModel
    @State private var pinchStartScale: CGFloat?

    public init(model: ControllerModel) {
        self.model = model
    }

    public var body: some View {
        GeometryReader { proxy in
            let bounds = proxy.size
            ZStack {
                if model.isEditing {
                    // Only exists while editing: a pinch recognizer active during play would
                    // read a stick plus a button press as a pinch and cancel those touches.
                    Color.black.opacity(0.35)
                        .contentShape(Rectangle())
                        .onTapGesture { model.selectedID = nil }
                        .gesture(pinchToResize)
                    if model.snapToGrid {
                        GridLines(spacing: ControllerModel.gridSize * 4)
                    }
                }

                ForEach(model.layout.elements) { element in
                    let frame = element.frame(in: bounds)
                    let isActive = model.input.activeElements.contains(element.id)
                    Group {
                        if model.isEditing {
                            EditableControl(element: element, model: model)
                        } else {
                            ControlView(
                                element: element,
                                buttons: model.input.state.buttons,
                                stick: model.input.sticks[element.id],
                                isActive: isActive
                            )
                            .opacity(model.layout.opacity * (isActive ? 1 : ControllerModel.idleOpacityFactor))
                        }
                    }
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                }

                if !model.isEditing {
                    TouchCaptureView(model: model)
                }
            }
            .frame(width: bounds.width, height: bounds.height)
            .onAppear { model.updateCanvasSize(bounds) }
            .onChange(of: bounds) { _, newBounds in model.updateCanvasSize(newBounds) }
            .onChange(of: !model.isEditing && model.layout.gyro.mode != .off, initial: true) { _, running in
                model.setGyroRunning(running)
            }
            .onDisappear { model.setGyroRunning(false) }
        }
    }

    /// Pinch on empty space to resize the selected control; small buttons are hard to pinch on.
    private var pinchToResize: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard let id = model.selectedID, let element = model.layout[id] else { return }
                let start = pinchStartScale ?? element.scale
                pinchStartScale = start
                model.resize(id, to: start * value.magnification)
            }
            .onEnded { _ in pinchStartScale = nil }
    }
}

/// One control in edit mode: drag to move, corner handle to resize.
private struct EditableControl: View {
    let element: ControlElement
    let model: ControllerModel
    @State private var dragStart: CGPoint?
    @State private var resizeStartScale: CGFloat?

    private var isSelected: Bool { model.selectedID == element.id }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ControlView(element: element, buttons: [], stick: nil, isActive: isSelected)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isSelected ? Color.accentColor : .white.opacity(0.6),
                            style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: isSelected ? [] : [5, 4])
                        )
                        .padding(-4)
                }
                .contentShape(Rectangle())
                .gesture(moveGesture)

            if isSelected {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .offset(x: 14, y: 14)
                    .gesture(resizeGesture)
            }
        }
    }

    private var moveGesture: some Gesture {
        // Global space: the view itself moves during the drag, so local translations would drift.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let start = dragStart ?? currentCenter
                dragStart = start
                model.selectedID = element.id
                model.move(element.id, to: CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height))
            }
            .onEnded { _ in dragStart = nil }
    }

    private var resizeGesture: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                let start = resizeStartScale ?? element.scale
                resizeStartScale = start
                // The center stays put, so pulling the corner out by d grows the half-width by d.
                let grow = (value.translation.width + value.translation.height) / 2
                model.resize(element.id, to: start + 2 * grow / element.kind.baseSize.width)
            }
            .onEnded { _ in resizeStartScale = nil }
    }

    private var currentCenter: CGPoint {
        let frame = element.frame(in: model.canvasSize)
        return CGPoint(x: frame.midX, y: frame.midY)
    }
}

private struct GridLines: View {
    let spacing: CGFloat

    var body: some View {
        Canvas { context, size in
            var path = Path()
            for x in stride(from: 0, through: size.width, by: spacing) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0, through: size.height, by: spacing) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.white.opacity(0.08)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// Transparent UIKit layer that reports every finger separately. SwiftUI gestures can't
/// track several simultaneous touches on different controls reliably.
private struct TouchCaptureView: UIViewRepresentable {
    let model: ControllerModel

    func makeUIView(context: Context) -> MultiTouchView {
        let view = MultiTouchView()
        view.model = model
        return view
    }

    func updateUIView(_ view: MultiTouchView, context: Context) {
        view.model = model
    }
}

private final class MultiTouchView: UIView {
    weak var model: ControllerModel?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            model?.touchBegan(ObjectIdentifier(touch), at: touch.location(in: self))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            model?.touchMoved(ObjectIdentifier(touch), to: touch.location(in: self))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            model?.touchEnded(ObjectIdentifier(touch))
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}
#endif
