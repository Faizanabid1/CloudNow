import Foundation

/// Saves layouts as one JSON file per profile in a directory.
public struct LayoutStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func names() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { $0.deletingPathExtension().lastPathComponent.removingPercentEncoding }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public func load(named name: String) throws -> ControllerLayout {
        try JSONDecoder().decode(ControllerLayout.self, from: Data(contentsOf: url(for: name)))
    }

    public func save(_ layout: ControllerLayout) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(layout).write(to: url(for: layout.name), options: .atomic)
    }

    public func delete(named name: String) throws {
        try FileManager.default.removeItem(at: url(for: name))
    }

    /// Profile names are user text, so they're percent-encoded into safe file names.
    private func url(for name: String) -> URL {
        let fileName = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? name
        return directory.appendingPathComponent(fileName).appendingPathExtension("json")
    }
}
