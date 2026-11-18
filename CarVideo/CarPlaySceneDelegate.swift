import CarPlay
import Combine

/// The CarPlay screen: a list of your MP4s. Tap one to play it.
/// The video goes to the car screen over AirPlay when the car is parked and supports
/// CarPlay video. Otherwise you hear the sound.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var listTemplate: CPListTemplate?
    private var libraryWatcher: AnyCancellable?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController

        let list = CPListTemplate(title: "My Videos", sections: [])
        list.tabImage = UIImage(systemName: "film")
        list.emptyViewTitleVariants = ["No videos yet"]
        list.emptyViewSubtitleVariants = ["Add MP4 files in the app on your iPhone"]
        listTemplate = list
        interfaceController.setRootTemplate(list, animated: true, completion: nil)

        VideoLibrary.shared.reload()
        libraryWatcher = VideoLibrary.shared.$videos
            .receive(on: DispatchQueue.main)
            .sink { [weak self] videos in self?.show(videos) }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        libraryWatcher = nil
        listTemplate = nil
        self.interfaceController = nil
    }

    private func show(_ videos: [VideoFile]) {
        let items: [CPListItem] = videos.map { video in
            let item = CPListItem(text: video.name,
                                  detailText: nil,
                                  image: UIImage(systemName: "film"))
            item.handler = { [weak self] _, completion in
                VideoPlayerManager.shared.play(video)
                self?.openNowPlaying()
                completion()
            }
            return item
        }
        listTemplate?.updateSections([CPListSection(items: items)])
    }

    private func openNowPlaying() {
        guard let controller = interfaceController,
              !(controller.topTemplate is CPNowPlayingTemplate) else { return }
        controller.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
    }
}
