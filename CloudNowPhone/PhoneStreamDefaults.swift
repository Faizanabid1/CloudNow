import Foundation

/// One-time changes to saved stream settings when an iPhone/iPad default changes.
enum PhoneStreamDefaults {
    private static let chromaMigrationKey = "phoneChroma420Default.v1"

    /// Earlier builds saved 4:4:4 as the default chroma. Move existing installs to 4:2:0
    /// once; a later choice of 4:4:4 in Settings is kept.
    /// Returns true when the settings changed and should be saved.
    @discardableResult
    static func migrate(_ settings: inout StreamSettings) -> Bool {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: chromaMigrationKey) else { return false }
        defaults.set(true, forKey: chromaMigrationKey)
        guard settings.chromaFormat != StreamSettings.defaultChromaFormat else { return false }
        settings.chromaFormat = StreamSettings.defaultChromaFormat
        return true
    }
}
