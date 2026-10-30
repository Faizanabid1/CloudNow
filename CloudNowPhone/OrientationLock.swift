import UIKit

/// Lets the app narrow its orientations at runtime. Menus follow the device; a stream locks to
/// landscape, so a portrait-held phone rotates the game instead of shrinking it.
final class PhoneAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLock.current
    }
}

enum OrientationLock {
    static var unlocked: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    private(set) static var current: UIInterfaceOrientationMask = unlocked

    static func set(_ mask: UIInterfaceOrientationMask) {
        current = mask
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        }
    }
}
