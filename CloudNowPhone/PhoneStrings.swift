/// iPhone/iPad wording for GeForce Now Duo, checked before the shared tables. The app name
/// applies in every language; the English entries replace Apple TV phrasing, and other
/// languages keep the shared translations. Format specifiers match the strings they replace.
enum PhoneStrings {
    static let appName = "GeForce Now Duo"

    static func text(for key: String, localeCode: String) -> String? {
        if key == "app_name" {
            return appName
        }
        guard localeCode.hasPrefix("en") else { return nil }
        return english[key]
    }

    private static let english: [String: String] = [
        "app_tagline": "GeForce NOW for iPhone and iPad",
        "gfn_frame_rate_display_unavailable":
            "%d fps requires a %d Hz display. This screen refreshes at up to %d Hz.",
        "gfn_frame_rate_display_and_membership_unavailable":
            "%d fps is unavailable because this screen is limited to %d Hz and your %@ membership does not include it at %@. Choose an included frame rate or resolution.",
        "chroma_sampling_description":
            "4:4:4 improves fine color detail. Experimental; requires H.265 and Ultimate.",
        "text_input_buttons_description":
            "Choose the controller button chord that opens the keyboard during streaming.",
        "text_input_hold_delay_description":
            "How long the text input buttons must be held before the keyboard opens. Default: 150 ms.",
        "cache_clear_failed_message": "GeForce Now Duo could not remove all cached data. %@",
        "reset_all_data_confirmation_message":
            "This signs you out and permanently removes all GeForce Now Duo data from this device. This action cannot be undone.",
        "reset_active_service_confirmation_message":
            "This signs you out and permanently removes your GeForce NOW data from this device. This action cannot be undone.",
        "controller_text_entry_title": "Type with Keyboard",
        "controller_text_entry_unsupported_characters":
            "This text includes characters GeForce Now Duo can't send yet. Edit the text and try again.",
        "controller_text_entry_unsupported_layout":
            "GeForce Now Duo can't send text with the selected keyboard layout yet. Choose a supported layout in Settings and try again.",
        "controller_text_entry_send_failed":
            "GeForce Now Duo couldn't send the text. Check your connection and try again.",
        "refresh_library_description": "Connected stores → cloud library → GeForce Now Duo.",
        "refresh_importing": "Updating GeForce Now Duo library…",
        "gfn_to_cloudnow": "Cloud library → GeForce Now Duo",
        "no_connected_libraries":
            "No sync-capable connected libraries were found. GeForce Now Duo will reload your cloud library.",
        "microphone_permission_denied_message":
            "Microphone access is disabled for GeForce Now Duo. Enable it in Settings > Privacy & Security > Microphone.",
    ]
}
