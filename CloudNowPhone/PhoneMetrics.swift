import SwiftUI

/// Sizes for the phone screens, chosen from the window width so one layout scales from an
/// upright iPhone, through the Duo and sideways iPhones, to a full-screen iPad.
nonisolated struct PhoneMetrics: Equatable, Sendable {
    let cardWidth: CGFloat
    let gridMinimum: CGFloat
    let heroHeight: CGFloat

    var gridMaximum: CGFloat {
        gridMinimum * 1.35
    }

    static func forWidth(_ width: CGFloat) -> PhoneMetrics {
        switch width {
        case ..<500:
            PhoneMetrics(cardWidth: 96, gridMinimum: 96, heroHeight: 180)
        case ..<1000:
            PhoneMetrics(cardWidth: 108, gridMinimum: 104, heroHeight: 220)
        default:
            PhoneMetrics(cardWidth: 150, gridMinimum: 150, heroHeight: 320)
        }
    }
}

extension EnvironmentValues {
    @Entry var phoneMetrics = PhoneMetrics.forWidth(700)
}
