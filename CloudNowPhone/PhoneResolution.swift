import UIKit

/// Picks the stream resolution that best fits this device's screen, so a phone gets a stream
/// shaped like its display instead of a TV's 16:9.
enum PhoneResolution {
    /// Bumped when the scoring changes so the corrected pick is applied once more.
    private static let appliedDefaultKey = "phoneResolutionDefaultApplied.v2"

    /// The screen in landscape pixels; streams are always played in landscape.
    static var screenPixels: CGSize {
        let screens = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }
        guard let size = screens.first?.nativeBounds.size else { return .zero }
        return CGSize(width: max(size.width, size.height), height: min(size.width, size.height))
    }

    /// Scores each resolution by how much of the screen it fills times how sharp it looks
    /// there (its pixels over the screen pixels it's drawn onto, capped at 1). Resolutions with
    /// more pixels than the screen only cost bandwidth, so they're skipped unless nothing else
    /// fits. "WxH" strings that don't parse are ignored.
    nonisolated static func bestMatch(from resolutions: [String], screen: CGSize) -> String? {
        guard screen.width > 0, screen.height > 0 else { return nil }
        let screenAspect = screen.width / screen.height
        let screenArea = screen.width * screen.height
        let parsed = resolutions.compactMap { label -> (label: String, area: CGFloat, score: CGFloat)? in
            let parts = label.split(separator: "x").compactMap { Double($0) }
            guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
            let area = parts[0] * parts[1]
            let aspect = parts[0] / parts[1]
            let coverage = min(aspect, screenAspect) / max(aspect, screenAspect)
            let sharpness = min(1, area / (screenArea * coverage))
            return (label, area, coverage * sharpness)
        }
        let fitting = parsed.filter { $0.area <= screenArea }
        guard !fitting.isEmpty else {
            return parsed.min { $0.area < $1.area }?.label
        }
        return fitting.max { ($0.score, $0.area) < ($1.score, $1.area) }?.label
    }

    /// Switches the stream to the best-fitting resolution once, the first time the account's
    /// resolutions are known. Later choices in Settings are left alone.
    static func applyDefaultIfNeeded(to viewModel: GamesViewModel) {
        guard viewModel.subscription != nil,
              !UserDefaults.standard.bool(forKey: appliedDefaultKey),
              let best = bestMatch(from: viewModel.availableResolutions, screen: screenPixels)
        else { return }
        viewModel.streamSettings.resolution = best
        UserDefaults.standard.set(true, forKey: appliedDefaultKey)
    }
}
