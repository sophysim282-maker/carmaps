import SwiftUI
import WebKit

/// Shows YouTube's official embedded player (allowed by YouTube's rules).
struct YouTubeView: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedID != videoID else { return }
        context.coordinator.loadedID = videoID

        let url = URL(string: "https://www.youtube.com/embed/\(videoID)?playsinline=1&autoplay=1")!
        var request = URLRequest(url: url)
        // YouTube asks apps to identify themselves, otherwise the player can show
        // "Video player configuration error".
        let appID = (Bundle.main.bundleIdentifier ?? "carvideo.app").lowercased()
        request.setValue("https://\(appID)", forHTTPHeaderField: "Referer")
        webView.load(request)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedID: String?
    }
}

/// Gets the 11-character video ID out of any normal YouTube link.
enum YouTubeLink {
    static func videoID(from text: String) -> String? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidID(input) { return input }

        let urlString = input.lowercased().hasPrefix("http") ? input : "https://" + input
        guard let parts = URLComponents(string: urlString),
              let host = parts.host?.lowercased() else { return nil }

        let pathPieces = parts.path.split(separator: "/").map(String.init)
        var candidate: String?

        if host.hasSuffix("youtu.be") {
            candidate = pathPieces.first                                   // youtu.be/ID
        } else if host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com") {
            if let v = parts.queryItems?.first(where: { $0.name == "v" })?.value {
                candidate = v                                              // watch?v=ID
            } else if pathPieces.count >= 2,
                      ["shorts", "embed", "live", "v"].contains(pathPieces[0]) {
                candidate = pathPieces[1]                                  // shorts/ID, live/ID
            }
        }

        guard let id = candidate, isValidID(id) else { return nil }
        return id
    }

    private static func isValidID(_ s: String) -> Bool {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return s.count == 11 && s.allSatisfy { allowed.contains($0) }
    }
}
