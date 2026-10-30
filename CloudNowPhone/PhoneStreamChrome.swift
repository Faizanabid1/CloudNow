import SwiftUI

extension View {
    /// Full-screen play: landscape, no status bar or home indicator over the game, and edge
    /// swipes go to the touch controls first instead of the system.
    func phoneStreamChrome() -> some View {
        statusBarHidden()
            .persistentSystemOverlays(.hidden)
            .defersSystemGestures(on: .all)
            .onAppear { OrientationLock.set(.landscape) }
            .onDisappear { OrientationLock.set(OrientationLock.unlocked) }
    }
}
