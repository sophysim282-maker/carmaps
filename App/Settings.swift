import Foundation
import CoreLocation
import AVFoundation

struct Place: Identifiable, Codable, Equatable {
    var name: String
    var address: String
    var lat: Double
    var lng: Double
    var id: String { "\(lat),\(lng),\(name)" }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

/// User settings + saved places, kept on the iPhone.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var language: String { didSet { d.set(language, forKey: "lang") } }
    @Published var theme: String { didSet { d.set(theme, forKey: "theme") } }
    @Published var voiceOn: Bool { didSet { d.set(voiceOn, forKey: "voice") } }
    @Published var home: Place? { didSet { Self.store(home, "home") } }
    @Published var work: Place? { didSet { Self.store(work, "work") } }
    @Published var favorites: [Place] { didSet { d.set(try? JSONEncoder().encode(favorites), forKey: "favs") } }

    static let languages: [(code: String, name: String)] = [
        ("en", "English"),
        ("km", "ខ្មែរ  Khmer"),
        ("zh-CN", "中文  Chinese"),
        ("th", "ไทย  Thai"),
        ("vi", "Tiếng Việt  Vietnamese"),
    ]

    init() {
        language = d.string(forKey: "lang") ?? "en"
        theme = d.string(forKey: "theme") ?? "auto"
        voiceOn = d.object(forKey: "voice") as? Bool ?? true
        home = Self.load("home")
        work = Self.load("work")
        favorites = d.data(forKey: "favs").flatMap { try? JSONDecoder().decode([Place].self, from: $0) } ?? []
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

    var voice: AVSpeechSynthesisVoice? {
        let lang = String(language.prefix(2))
        return AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix(lang) }
    }

    var voiceAvailable: Bool { voice != nil }

    func isFavorite(_ p: Place) -> Bool { favorites.contains(p) }

    func toggleFavorite(_ p: Place) {
        if let i = favorites.firstIndex(of: p) { favorites.remove(at: i) } else { favorites.append(p) }
    }

    private static func store(_ p: Place?, _ key: String) {
        UserDefaults.standard.set(p.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }

    private static func load(_ key: String) -> Place? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Place.self, from: $0) }
    }
}
