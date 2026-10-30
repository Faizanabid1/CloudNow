import SwiftUI

// Stand-ins for SwiftUI APIs that exist only on tvOS, so the shared CloudNow views compile
// unchanged for iPhone and iPad. Swift ranks these available declarations above SwiftUI's
// unavailable ones. Remote-only commands have no touch equivalent and become no-ops; touch
// screens get back navigation from their navigation containers instead.

enum MoveCommandDirection: Sendable {
    case up, down, left, right
}

extension View {
    /// Focus sections only steer the tvOS focus engine.
    func focusSection() -> some View {
        self
    }

    /// The Siri Remote Menu/Back button has no touch equivalent.
    func onExitCommand(perform action: (() -> Void)?) -> some View {
        self
    }

    /// The Siri Remote Play/Pause button has no touch equivalent.
    func onPlayPauseCommand(perform action: (() -> Void)?) -> some View {
        self
    }

    /// Remote swipes have no touch equivalent; touch screens scroll instead.
    func onMoveCommand(perform action: ((MoveCommandDirection) -> Void)?) -> some View {
        self
    }
}

extension PrimitiveButtonStyle where Self == PlainButtonStyle {
    /// tvOS card buttons lift and tilt under focus; on touch screens they're plain buttons.
    static var card: PlainButtonStyle {
        .plain
    }
}
