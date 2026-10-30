import CoreGraphics
import Foundation

/// A named arrangement of on-screen controls, saved as one profile.
public struct ControllerLayout: Codable, Hashable, Sendable {
    public static let scaleRange: ClosedRange<CGFloat> = 0.5...2.5

    public var name: String
    public var elements: [ControlElement]
    /// Opacity of the controls while playing.
    public var opacity: Double
    /// When on, a stick's base re-centers wherever the thumb lands inside its area.
    public var floatingSticks: Bool
    /// Optional so layouts saved before gyro support still decode; nil means off.
    private var gyroSettings: GyroSettings?

    public var gyro: GyroSettings {
        get { gyroSettings ?? GyroSettings() }
        set { gyroSettings = newValue }
    }

    public init(name: String, elements: [ControlElement], opacity: Double = 0.8, floatingSticks: Bool = false) {
        self.name = name
        self.elements = elements
        self.opacity = opacity
        self.floatingSticks = floatingSticks
    }

    public subscript(id: UUID) -> ControlElement? {
        elements.first { $0.id == id }
    }

    /// Moves a control's center to `point` (overlay coordinates), optionally snapping it to a
    /// grid, and keeps the whole control on screen.
    public mutating func move(_ id: UUID, to point: CGPoint, in bounds: CGSize, grid: CGFloat? = nil) {
        guard let index = elements.firstIndex(where: { $0.id == id }),
              bounds.width > 0, bounds.height > 0 else { return }
        var point = point
        if let grid, grid > 0 {
            point.x = (point.x / grid).rounded() * grid
            point.y = (point.y / grid).rounded() * grid
        }
        let size = elements[index].size
        let halfWidth = min(size.width, bounds.width) / 2
        let halfHeight = min(size.height, bounds.height) / 2
        point.x = point.x.clamped(to: halfWidth...(bounds.width - halfWidth))
        point.y = point.y.clamped(to: halfHeight...(bounds.height - halfHeight))
        elements[index].center = CGPoint(x: point.x / bounds.width, y: point.y / bounds.height)
    }

    public mutating func resize(_ id: UUID, to scale: CGFloat, in bounds: CGSize) {
        guard let index = elements.firstIndex(where: { $0.id == id }) else { return }
        elements[index].scale = scale.clamped(to: Self.scaleRange)
        // A control that grew near an edge gets pushed back on screen.
        let frame = elements[index].frame(in: bounds)
        move(id, to: CGPoint(x: frame.midX, y: frame.midY), in: bounds)
    }

    @discardableResult
    public mutating func add(_ kind: ControlKind) -> UUID {
        let element = ControlElement(kind: kind, center: CGPoint(x: 0.5, y: 0.5))
        elements.append(element)
        return element.id
    }

    public mutating func remove(_ id: UUID) {
        elements.removeAll { $0.id == id }
    }

    /// The control under `point`. Hit areas are padded by `slop` for fat fingers; where padded
    /// areas overlap, the control whose center is nearest wins.
    public func element(at point: CGPoint, in bounds: CGSize, slop: CGFloat = 12) -> ControlElement? {
        elements
            .map { (element: $0, frame: $0.frame(in: bounds)) }
            .filter { $0.frame.insetBy(dx: -slop, dy: -slop).contains(point) }
            .min { distance($0.frame, point) < distance($1.frame, point) }?
            .element
    }

    private func distance(_ frame: CGRect, _ point: CGPoint) -> CGFloat {
        hypot(frame.midX - point.x, frame.midY - point.y)
    }

    /// Xbox-style landscape layout: sticks and pads in the lower corners, shoulders along the top.
    /// Controls are placed in points from the screen edges, so spacing holds on any aspect
    /// ratio, then stored as fractions like any other layout.
    public static func standard(in bounds: CGSize) -> ControllerLayout {
        let bounds = bounds.width > 0 && bounds.height > 0 ? bounds : CGSize(width: 852, height: 393)
        let w = bounds.width
        let h = bounds.height
        let margin: CGFloat = 16
        let gap: CGFloat = 8
        let topRow = margin + 22
        let shoulder = margin + 76 + gap + 38
        let stickX = margin + 68
        let padX = margin + 136 + gap + 68
        let bottomRow = h - margin - 68
        let face = CGPoint(x: w - margin - 28 - 62, y: h / 2)

        let placements: [(ControlKind, CGPoint)] = [
            (.trigger(.left), CGPoint(x: margin + 38, y: topRow)),
            (.button(.leftShoulder), CGPoint(x: shoulder, y: topRow)),
            (.button(.back), CGPoint(x: w / 2 - 54, y: topRow)),
            (.button(.guide), CGPoint(x: w / 2, y: topRow)),
            (.button(.start), CGPoint(x: w / 2 + 54, y: topRow)),
            (.button(.rightShoulder), CGPoint(x: w - shoulder, y: topRow)),
            (.trigger(.right), CGPoint(x: w - margin - 38, y: topRow)),
            (.stick(.left), CGPoint(x: stickX, y: h / 2)),
            (.dpad, CGPoint(x: padX, y: bottomRow)),
            (.button(.y), CGPoint(x: face.x, y: face.y - 62)),
            (.button(.x), CGPoint(x: face.x - 62, y: face.y)),
            (.button(.b), CGPoint(x: face.x + 62, y: face.y)),
            (.button(.a), CGPoint(x: face.x, y: face.y + 62)),
            (.stick(.right), CGPoint(x: w - padX, y: bottomRow)),
        ]
        return ControllerLayout(name: "Default", elements: placements.map { kind, point in
            ControlElement(kind: kind, center: CGPoint(x: point.x / w, y: point.y / h))
        })
    }
}
