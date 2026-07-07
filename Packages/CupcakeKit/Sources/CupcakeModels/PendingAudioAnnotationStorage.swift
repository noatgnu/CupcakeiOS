import Foundation

/// Persists a not-yet-synced annotation file (audio, photo, video, or sketch) between app launches.
public enum PendingAnnotationFileStorage {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("PendingAnnotationFiles", isDirectory: true)
    }

    public static func persist(_ sourceURL: URL, clientID: UUID, fileExtension: String) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = "\(clientID.uuidString).\(fileExtension)"
        let destinationURL = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return fileName
    }

    public static func persist(_ data: Data, clientID: UUID, fileExtension: String) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = "\(clientID.uuidString).\(fileExtension)"
        let destinationURL = directory.appendingPathComponent(fileName)
        try data.write(to: destinationURL)
        return fileName
    }

    public static func url(forFileName fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    public static func remove(fileName: String) {
        try? FileManager.default.removeItem(at: url(forFileName: fileName))
    }
}
