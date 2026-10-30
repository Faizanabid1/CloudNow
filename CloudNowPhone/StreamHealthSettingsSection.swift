import SwiftUI

/// Settings entry for sharing the per-second stream health logs recorded during streams.
struct StreamHealthSettingsSection: View {
    @State private var files: [URL] = []

    var body: some View {
        Section {
            if let latest = files.first {
                ShareLink(item: latest) {
                    Label("Share Latest Stream Log", systemImage: "square.and.arrow.up")
                }
                if files.count > 1 {
                    Menu {
                        ForEach(files.dropFirst(), id: \.self) { file in
                            ShareLink(item: file) {
                                Text(Self.title(for: file))
                            }
                        }
                    } label: {
                        Label("Share an Earlier Log", systemImage: "clock.arrow.circlepath")
                    }
                }
                Text("Latest: \(Self.title(for: latest))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("No logs yet. One is recorded during every stream.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Stream Health Log")
        } footer: {
            Text(
                "Once a second during a stream, the app records frame rate, bitrate, packet loss, "
                    + "freezes, decoder resets, heat and display refresh rate. Share the log after a "
                    + "stutter to find what caused it. The last 10 streams are kept."
            )
        }
        .onAppear { files = StreamHealthLogger.logFiles() }
    }

    private static func title(for file: URL) -> String {
        let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return date?.formatted(date: .abbreviated, time: .shortened) ?? file.lastPathComponent
    }
}
