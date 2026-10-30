#if canImport(UIKit)
import SwiftUI
import VirtualControllerKit

/// How a control looks. Purely visual; touches are handled by the overlay.
struct ControlView: View {
    let element: ControlElement
    let buttons: GamepadButtons
    let stick: StickVisual?
    let isActive: Bool

    var body: some View {
        switch element.kind {
        case .button(let id):
            ButtonFace(id: id, pressed: isActive)
        case .trigger(let side):
            Face(shape: RoundedRectangle(cornerRadius: 10), label: side == .left ? "LT" : "RT", tint: .white, pressed: isActive)
        case .stick(let side):
            StickFace(label: side == .left ? "L" : "R", visual: stick)
        case .dpad:
            DpadFace(buttons: buttons)
        }
    }
}

private struct ButtonFace: View {
    let id: ButtonID
    let pressed: Bool

    var body: some View {
        switch id {
        case .leftShoulder, .rightShoulder:
            Face(shape: Capsule(), label: id.label, tint: .white, pressed: pressed)
        case .back, .start, .guide:
            Face(shape: Circle(), symbol: symbol, tint: .white, pressed: pressed)
        default:
            Face(shape: Circle(), label: id.label, tint: tint, pressed: pressed)
        }
    }

    private var tint: Color {
        switch id {
        case .a: .green
        case .b: .red
        case .x: .blue
        case .y: .yellow
        default: .white
        }
    }

    private var symbol: String {
        switch id {
        case .back: "rectangle.on.rectangle"
        case .start: "line.3.horizontal"
        default: "house.fill"
        }
    }
}

/// A shape with a label or symbol, sized to fill whatever frame the layout gives it.
private struct Face<S: Shape>: View {
    let shape: S
    var label: String?
    var symbol: String?
    let tint: Color
    let pressed: Bool

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                shape.fill(.white.opacity(pressed ? 0.45 : 0.15))
                shape.stroke(.white.opacity(0.7), lineWidth: 1.5)
                Group {
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: side * 0.38, weight: .semibold))
                    } else if let label {
                        Text(label).font(.system(size: side * 0.42, weight: .bold, design: .rounded))
                    }
                }
                .foregroundStyle(tint)
                .minimumScaleFactor(0.5)
            }
        }
        .scaleEffect(pressed ? 0.94 : 1)
    }
}

private struct StickFace: View {
    let label: String
    let visual: StickVisual?

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let knobSize = size * 0.45
            let travel = (size - knobSize) / 2
            ZStack {
                Circle().fill(.white.opacity(0.1))
                Circle().stroke(.white.opacity(0.6), lineWidth: 1.5)
                Circle()
                    .fill(.white.opacity(visual == nil ? 0.3 : 0.55))
                    .overlay(Text(label).font(.system(size: knobSize * 0.35, weight: .bold, design: .rounded)))
                    .frame(width: knobSize, height: knobSize)
                    .offset(x: (visual?.knob.dx ?? 0) * travel, y: (visual?.knob.dy ?? 0) * travel)
            }
            .frame(width: size, height: size)
            .offset(x: visual?.baseOffset.dx ?? 0, y: visual?.baseOffset.dy ?? 0)
        }
    }
}

private struct DpadFace: View {
    let buttons: GamepadButtons

    var body: some View {
        GeometryReader { proxy in
            let arm = min(proxy.size.width, proxy.size.height) / 3
            ZStack {
                Rectangle().fill(.white.opacity(0.15)).frame(width: arm, height: arm)
                armView(.dpadUp, "arrowtriangle.up.fill", arm: arm, x: 0, y: -arm)
                armView(.dpadDown, "arrowtriangle.down.fill", arm: arm, x: 0, y: arm)
                armView(.dpadLeft, "arrowtriangle.left.fill", arm: arm, x: -arm, y: 0)
                armView(.dpadRight, "arrowtriangle.right.fill", arm: arm, x: arm, y: 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func armView(_ direction: GamepadButtons, _ symbol: String, arm: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        let pressed = buttons.contains(direction)
        return RoundedRectangle(cornerRadius: arm * 0.2)
            .fill(.white.opacity(pressed ? 0.45 : 0.15))
            .overlay(RoundedRectangle(cornerRadius: arm * 0.2).stroke(.white.opacity(0.7), lineWidth: 1.5))
            .overlay(Image(systemName: symbol).font(.system(size: arm * 0.35)).foregroundStyle(.white))
            .frame(width: arm, height: arm)
            .offset(x: x, y: y)
    }
}
#endif
