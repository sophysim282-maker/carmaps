import SwiftUI
import AVKit
import UniformTypeIdentifiers
import PhotosUI
import CoreTransferable

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
    @State private var showFilePicker = false
    @State private var showPhotoPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isImporting = false
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
                                               description: Text("Tap + to add videos from Photos or Files."))
                    }
                }
            }
            .navigationTitle("My Videos")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AirPlayButton().frame(width: 32, height: 32)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showPhotoPicker = true } label: {
                            Label("From Photos", systemImage: "photo.on.rectangle")
                        }
                        Button { showFilePicker = true } label: {
                            Label("From Files", systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .overlay {
                if isImporting {
                    ProgressView("Adding video…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            // Files app: the system copies the file for us (asCopy), so no permission problems.
            .sheet(isPresented: $showFilePicker) {
                DocumentPicker { urls in
                    for url in urls {
                        do { try library.importVideo(from: url) }
                        catch { errorText = "Couldn't add \(url.lastPathComponent): \(error.localizedDescription)" }
                    }
                }
                .ignoresSafeArea()
            }
            // Photos app videos.
            .photosPicker(isPresented: $showPhotoPicker,
                          selection: $photoItems,
                          matching: .videos)
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                isImporting = true
                Task {
                    for item in items {
                        do {
                            if let movie = try await item.loadTransferable(type: PickedMovie.self) {
                                try library.importVideo(from: movie.url)
                                try? FileManager.default.removeItem(at: movie.url)
                            } else {
                                errorText = "Couldn't read that video."
                            }
                        } catch {
                            errorText = "Couldn't add video: \(error.localizedDescription)"
                        }
                    }
                    photoItems = []
                    isImporting = false
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
