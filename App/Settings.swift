import Foundation
import CoreLocation
import AVFoundation

struct Place: Identifiable, Codable, Equatable {
    var name: String
    var address: String
    var lat: Double
    var lng: Double
    var placeId: String?
    var id: String { "\(lat),\(lng),\(name)" }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    func same(_ o: Place?) -> Bool { o != nil && o!.lat == lat && o!.lng == lng }
}

/// User settings, saved places and recents, kept on the iPhone.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var language: String { didSet { d.set(language, forKey: "lang") } }
    @Published var theme: String { didSet { d.set(theme, forKey: "theme") } }
    @Published var mapType: String { didSet { d.set(mapType, forKey: "mapType") } }
    @Published var traffic: Bool { didSet { d.set(traffic, forKey: "traffic") } }
    @Published var voiceOn: Bool { didSet { d.set(voiceOn, forKey: "voice") } }
    @Published var avoidTolls: Bool { didSet { d.set(avoidTolls, forKey: "avoidTolls") } }
    @Published var avoidHighways: Bool { didSet { d.set(avoidHighways, forKey: "avoidHighways") } }
    @Published var avoidFerries: Bool { didSet { d.set(avoidFerries, forKey: "avoidFerries") } }
    @Published var home: Place? { didSet { Self.store(home, "home") } }
    @Published var work: Place? { didSet { Self.store(work, "work") } }
    @Published var favorites: [Place] { didSet { Self.storeList(favorites, "favs") } }
    @Published var recents: [Place] { didSet { Self.storeList(recents, "recents") } }

    static let languages: [(code: String, name: String)] = [
        ("en", "English"),
        ("km", "ខ្មែរ  Khmer"),
        ("zh-CN", "中文  Chinese"),
        ("th", "ไทย  Thai"),
        ("vi", "Tiếng Việt  Vietnamese"),
    ]
    static let speechLocales = ["en": "en-US", "km": "km-KH", "zh-CN": "zh-CN", "th": "th-TH", "vi": "vi-VN"]

    init() {
        language = d.string(forKey: "lang") ?? "en"
        theme = d.string(forKey: "theme") ?? "auto"
        mapType = d.string(forKey: "mapType") ?? "normal"
        traffic = Self.bool("traffic", true)
        voiceOn = Self.bool("voice", true)
        avoidTolls = Self.bool("avoidTolls", false)
        avoidHighways = Self.bool("avoidHighways", false)
        avoidFerries = Self.bool("avoidFerries", false)
        home = Self.load("home")
        work = Self.load("work")
        favorites = Self.loadList("favs")
        recents = Self.loadList("recents")
    }

    var isNight: Bool {
        switch theme {
        case "night": return true
        case "day": return false
        default:
            let h = Calendar.current.component(.hour, from: Date())
            return h >= 18 || h < 6
        }
    }

    var darkControls: Bool { isNight || mapType == "satellite" }

    var voice: AVSpeechSynthesisVoice? {
        let lang = String(language.prefix(2))
        return AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix(lang) }
    }

    var voiceAvailable: Bool { voice != nil }

    func isFavorite(_ p: Place) -> Bool { favorites.contains { $0.same(p) } }

    func toggleFavorite(_ p: Place) {
        if let i = favorites.firstIndex(where: { $0.same(p) }) { favorites.remove(at: i) } else { favorites.append(p) }
    }

    func addRecent(_ p: Place) {
        var r = recents.filter { !$0.same(p) }
        r.insert(p, at: 0)
        recents = Array(r.prefix(15))
    }

    private static func bool(_ key: String, _ def: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? def
    }
    private static func store(_ p: Place?, _ key: String) {
        UserDefaults.standard.set(p.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }
    private static func load(_ key: String) -> Place? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Place.self, from: $0) }
    }
    private static func storeList(_ list: [Place], _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: key)
    }
    private static func loadList(_ key: String) -> [Place] {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([Place].self, from: $0) } ?? []
    }
}
