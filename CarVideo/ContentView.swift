import SwiftUI
import AVKit
import UniformTypeIdentifiers

/// iPhone screen with two tabs: your own MP4s, and YouTube.
struct ContentView: View {
    var body: some View {
        TabView {
            MyVideosView()
                .tabItem { Label("My Videos", systemImage: "film") }
            YouTubeTab()
                .tabItem { Label("YouTube", systemImage: "play.rectangle") }
        }
    }
}

// MARK: - My Videos (MP4 files)

struct MyVideosView: View {
    @ObservedObject private var library = VideoLibrary.shared
    @ObservedObject private var manager = VideoPlayerManager.shared
    @State private var showImporter = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if manager.current != nil {
                    VideoPlayer(player: manager.player)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .background(.black)
                }

                List {
                    ForEach(library.videos) { video in
                        Button {
                            manager.play(video)
                        } label: {
                            Label(video.name,
                                  systemImage: manager.current == video ? "play.circle.fill" : "film")
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in
                        offsets.map { library.videos[$0] }.forEach(library.delete)
                    }
                }
                .overlay {
                    if library.videos.isEmpty {
                        ContentUnavailableView("No videos yet",
                                               systemImage: "film",
                                               description: Text("Tap + to add MP4 files from the Files app."))
                    }
                }
            }
            .navigationTitle("My Videos")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AirPlayButton().frame(width: 32, height: 32)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showImporter = true } label: { Image(systemName: "plus") }
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.movie],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    for url in urls {
                        do { try library.importVideo(from: url) }
                        catch { errorText = "Couldn't add \(url.lastPathComponent): \(error.localizedDescription)" }
                    }
                case .failure(let error):
                    errorText = error.localizedDescription
                }
            }
            .alert("Problem", isPresented: Binding(get: { errorText != nil },
                                                   set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }
}

// MARK: - YouTube

struct YouTubeTab: View {
    @State private var link = ""
    @State private var videoID: String?
    @State private var badLink = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("Paste a YouTube link", text: $link)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .onSubmit(load)
                    Button("Play", action: load)
                        .buttonStyle(.borderedProminent)
                }

                if badLink {
                    Text("That doesn't look like a YouTube video link.")
                        .foregroundStyle(.red)
                }

                if let id = videoID {
                    YouTubeView(videoID: id)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Text("To show it on the car screen, tap the AirPlay icon inside the player. This only works when parked, in a car that supports CarPlay video.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("YouTube")
        }
    }

    private func load() {
        if let id = YouTubeLink.videoID(from: link) {
            videoID = id
            badLink = false
        } else {
            badLink = true
        }
    }
}

// MARK: - AirPlay button

/// The standard AirPlay button. Pick the car to send video to the CarPlay screen.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = true
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
