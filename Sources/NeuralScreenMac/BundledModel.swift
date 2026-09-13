import Foundation

/// One fixed model for both workspaces. The packaged app is self-contained;
/// only command-line development builds use the project's Models directory.
enum BundledModel {
    static let name = "NR.dlss"

    static func url() throws -> URL {
        let location: URL
        if Bundle.main.bundleURL.pathExtension == "app", let resources = Bundle.main.resourceURL {
            location = resources.appendingPathComponent(name, isDirectory: true)
        } else {
            location = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true).appendingPathComponent(name, isDirectory: true)
        }
        guard ["manifest.json", "weights.safetensors"].allSatisfy({
            FileManager.default.isReadableFile(atPath: location.appendingPathComponent($0).path)
        }) else {
            throw PortError.message("The built-in NR.dlss model is missing or incomplete. Restore the complete application and restart it.")
        }
        return location
    }
}
