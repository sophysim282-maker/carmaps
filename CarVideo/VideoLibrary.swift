import Foundation
import Combine

/// One video file stored inside the app.
struct VideoFile: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

/// Keeps the list of MP4 / MOV files saved in the app's "Videos" folder.
final class VideoLibrary: ObservableObject {
    static let shared = VideoLibrary()

    @Published private(set) var videos: [VideoFile] = []
    let folder: URL

    private let allowedExtensions = ["mp4", "m4v", "mov"]

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = documents.appendingPathComponent("Videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder,
                                                                  includingPropertiesForKeys: nil)) ?? []
        videos = files
            .filter { allowedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { VideoFile(url: $0) }
    }

    /// Copies a video picked from the Files app into the app.
    func importVideo(from source: URL) throws {
        let hasAccess = source.startAccessingSecurityScopedResource()
        defer { if hasAccess { source.stopAccessingSecurityScopedResource() } }

        let baseName = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var destination = folder.appendingPathComponent(source.lastPathComponent)
        var number = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = folder.appendingPathComponent("\(baseName) \(number).\(ext)")
            number += 1
        }
        try FileManager.default.copyItem(at: source, to: destination)
        reload()
    }

    func delete(_ video: VideoFile) {
        try? FileManager.default.removeItem(at: video.url)
        reload()
    }
}
