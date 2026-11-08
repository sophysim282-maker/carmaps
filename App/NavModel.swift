import Foundation
import CoreLocation
import AVFoundation
import GoogleMaps

struct Suggestion: Identifiable {
    let id: String
    let main: String
    let secondary: String
}

struct Step {
    let instruction: String
    let maneuver: String
    let distance: Double
    let end: CLLocationCoordinate2D
}

/// Search, route preview and turn-by-turn guidance (Google Places API New + Routes API).
final class NavModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    let apiKey: String
    let settings = Settings.shared

    @Published var location: CLLocation?
    @Published var results: [Place] = []
    @Published var suggestions: [Suggestion] = []
    @Published var selected: Place?
    @Published var path: GMSPath?
    @Published var steps: [Step] = []
    @Published var guiding = false
    @Published var stepIndex = 0
    @Published var distanceToNext: Double = 0
    @Published var remainingMeters: Double = 0
    @Published var remainingSeconds: Double = 0
    @Published var status = ""

    /// Each time something is spoken, the car page gets it too.
    private(set) var spokenText = ""
    private(set) var spokenId = 0

    private let manager = CLLocationManager()
    private let speech = AVSpeechSynthesizer()
    private var totalMeters: Double = 0
    private var totalSeconds: Double = 0
    private var saidFar = false
    private var saidNear = false
    private var lastReroute = Date.distantPast
    private var routing = false
    private var sessionToken = UUID().uuidString
    private var autoWork: DispatchWorkItem?

    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt,
                                                         options: [.duckOthers, .mixWithOthers])
    }

    // MARK: - Text for screens

    var nextInstruction: String {
        guard guiding, !steps.isEmpty else { return "" }
        if stepIndex + 1 < steps.count { return steps[stepIndex + 1].instruction }
        return "Arrive at destination"
    }

    var nextManeuver: String {
        guard guiding, stepIndex + 1 < steps.count else { return "ARRIVE" }
        return steps[stepIndex + 1].maneuver
    }

    var arrivalText: String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: Date().addingTimeInterval(remainingSeconds))
    }

    // MARK: - Location

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }
        let first = location == nil
        location = loc
        if first, selected != nil, path == nil { fetchRoute() }
        if guiding { progress(loc) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        manager.startUpdatingLocation()
    }

    // MARK: - Search

    func search(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        autoWork?.cancel()
        suggestions = []
        status = "Searching…"
        var body: [String: Any] = ["textQuery": q, "pageSize": 8, "languageCode": settings.language]
        if let l = location {
            body["locationBias"] = ["circle": ["center": ["latitude": l.coordinate.latitude,
                                                          "longitude": l.coordinate.longitude],
                                               "radius": 50000.0]]
        }
        post("https://places.googleapis.com/v1/places:searchText", body: body,
             fields: "places.displayName,places.formattedAddress,places.location") { [weak self] json in
            guard let self else { return }
            let places = (json["places"] as? [[String: Any]]) ?? []
            self.results = places.compactMap { p in
                guard let loc = p["location"] as? [String: Any],
                      let lat = loc["latitude"] as? Double, let lng = loc["longitude"] as? Double else { return nil }
                let name = (p["displayName"] as? [String: Any])?["text"] as? String ?? "Place"
                return Place(name: name, address: p["formattedAddress"] as? String ?? "", lat: lat, lng: lng)
            }
            self.status = self.results.isEmpty ? "Nothing found" : ""
        }
    }

    // MARK: - Suggestions while typing (Places Autocomplete)

    func autocomplete(_ text: String) {
        autoWork?.cancel()
        let q = text.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { suggestions = []; return }
        let work = DispatchWorkItem { [weak self] in self?.runAutocomplete(q) }
        autoWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func runAutocomplete(_ q: String) {
        var body: [String: Any] = ["input": q, "languageCode": settings.language, "sessionToken": sessionToken]
        if let l = location {
            body["locationBias"] = ["circle": ["center": ["latitude": l.coordinate.latitude,
                                                          "longitude": l.coordinate.longitude],
                                               "radius": 50000.0]]
        }
        call("https://places.googleapis.com/v1/places:autocomplete", body: body,
             fields: "suggestions.placePrediction.placeId,suggestions.placePrediction.structuredFormat,suggestions.placePrediction.text",
             quiet: true) { [weak self] json in
            guard let self else { return }
            let list = (json["suggestions"] as? [[String: Any]]) ?? []
            self.suggestions = list.compactMap { item in
                guard let pp = item["placePrediction"] as? [String: Any], let id = pp["placeId"] as? String else { return nil }
                let sf = pp["structuredFormat"] as? [String: Any]
                let main = (sf?["mainText"] as? [String: Any])?["text"] as? String
                    ?? (pp["text"] as? [String: Any])?["text"] as? String ?? ""
                let secondary = (sf?["secondaryText"] as? [String: Any])?["text"] as? String ?? ""
                return Suggestion(id: id, main: main, secondary: secondary)
            }
        }
    }

    func choose(_ s: Suggestion) {
        autoWork?.cancel()
        suggestions = []
        status = "Loading…"
        let url = "https://places.googleapis.com/v1/places/\(s.id)?languageCode=\(settings.language)&sessionToken=\(sessionToken)"
        sessionToken = UUID().uuidString
        call(url, body: nil, fields: "displayName,formattedAddress,location") { [weak self] json in
            guard let self, let loc = json["location"] as? [String: Any],
                  let lat = loc["latitude"] as? Double, let lng = loc["longitude"] as? Double else {
                self?.status = "Could not open this place"
                return
            }
            let name = (json["displayName"] as? [String: Any])?["text"] as? String ?? s.main
            self.status = ""
            self.select(Place(name: name, address: json["formattedAddress"] as? String ?? s.secondary, lat: lat, lng: lng))
        }
    }

    // MARK: - Preview / start / stop

    /// Show the place and its route (like tapping a place in Google Maps).
    func select(_ place: Place) {
        endGuidance()
        selected = place
        results = []
        path = nil
        steps = []
        fetchRoute()
    }

    func startGuidance() {
        guard !steps.isEmpty else { return }
        guiding = true
        stepIndex = 0
        saidFar = false
        saidNear = false
        lastReroute = Date()
        say(steps[0].instruction)
        if let l = location { progress(l) }
    }

    func endGuidance() {
        guiding = false
        speech.stopSpeaking(at: .immediate)
    }

    func clear() {
        endGuidance()
        selected = nil
        path = nil
        steps = []
        status = ""
    }

    // MARK: - Route (Routes API)

    private func fetchRoute() {
        guard let dest = selected else { return }
        guard let here = location else { status = "Waiting for GPS…"; return }
        guard !routing else { return }
        routing = true
        lastReroute = Date()
        status = guiding ? "Re-routing…" : "Finding route…"
        func ll(_ c: CLLocationCoordinate2D) -> [String: Any] {
            ["location": ["latLng": ["latitude": c.latitude, "longitude": c.longitude]]]
        }
        let body: [String: Any] = [
            "origin": ll(here.coordinate),
            "destination": ll(dest.coordinate),
            "travelMode": "DRIVE",
            "routingPreference": "TRAFFIC_AWARE",
            "languageCode": settings.language,
            "units": "METRIC",
        ]
        let fields = "routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline," +
            "routes.legs.steps.distanceMeters,routes.legs.steps.endLocation,routes.legs.steps.navigationInstruction"
        post("https://routes.googleapis.com/directions/v2:computeRoutes", body: body, fields: fields) { [weak self] json in
            guard let self else { return }
            self.routing = false
            guard self.selected == dest,
                  let r = (json["routes"] as? [[String: Any]])?.first,
                  let enc = (r["polyline"] as? [String: Any])?["encodedPolyline"] as? String else {
                if self.selected == dest { self.status = "No route found" }
                return
            }
            var newSteps: [Step] = []
            for leg in (r["legs"] as? [[String: Any]]) ?? [] {
                for s in (leg["steps"] as? [[String: Any]]) ?? [] {
                    let ni = s["navigationInstruction"] as? [String: Any]
                    let end = ((s["endLocation"] as? [String: Any])?["latLng"] as? [String: Any]) ?? [:]
                    newSteps.append(Step(
                        instruction: (ni?["instructions"] as? String ?? "Continue")
                            .replacingOccurrences(of: "\n", with: " "),
                        maneuver: ni?["maneuver"] as? String ?? "STRAIGHT",
                        distance: Double(s["distanceMeters"] as? Int ?? 0),
                        end: CLLocationCoordinate2D(latitude: end["latitude"] as? Double ?? 0,
                                                    longitude: end["longitude"] as? Double ?? 0)))
                }
            }
            guard !newSteps.isEmpty else { self.status = "No route found"; return }
            self.path = GMSPath(fromEncodedPath: enc)
            self.steps = newSteps
            self.stepIndex = 0
            self.totalMeters = Double(r["distanceMeters"] as? Int ?? 0)
            self.totalSeconds = Double((r["duration"] as? String ?? "0s").dropLast()) ?? 0
            self.remainingMeters = self.totalMeters
            self.remainingSeconds = self.totalSeconds
            self.saidFar = false
            self.saidNear = false
            self.status = ""
            if self.guiding, let l = self.location { self.progress(l) }
        }
    }

    // MARK: - Turn-by-turn

    private func progress(_ loc: CLLocation) {
        guard stepIndex < steps.count else { return }

        func dist(_ i: Int) -> Double {
            loc.distance(from: CLLocation(latitude: steps[i].end.latitude, longitude: steps[i].end.longitude))
        }
        var d = dist(stepIndex)
        while d < 25, stepIndex < steps.count - 1 {
            stepIndex += 1
            saidFar = false
            saidNear = false
            d = dist(stepIndex)
        }
        distanceToNext = d

        let after = steps.dropFirst(stepIndex + 1).reduce(0) { $0 + $1.distance }
        remainingMeters = d + after
        remainingSeconds = totalMeters > 0 ? totalSeconds * remainingMeters / totalMeters : 0

        if stepIndex == steps.count - 1, d < 30 {
            say(settings.language == "en" ? "You have arrived" : nextInstruction)
            clear()
            status = "Arrived ✅"
            return
        }

        if !saidFar, d < 500, d > 200, steps[stepIndex].distance > 700 {
            saidFar = true
            say(settings.language == "en" ? "In \(Self.distanceText(d)), \(nextInstruction)" : nextInstruction)
        }
        if !saidNear, d < 80 {
            saidNear = true
            saidFar = true
            say(nextInstruction)
        }

        if let p = path, Date().timeIntervalSince(lastReroute) > 10,
           !GMSGeometryIsLocationOnPathTolerance(loc.coordinate, p, true, 60) {
            fetchRoute()
        }
    }

    private func say(_ text: String) {
        spokenText = text
        spokenId += 1
        guard settings.voiceOn else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = settings.voice
        speech.speak(u)
    }

    static func distanceText(_ m: Double) -> String {
        if m >= 1000 { return String(format: "%.1f km", m / 1000) }
        if m >= 100 { return "\(Int((m / 50).rounded()) * 50) m" }
        return "\(Int((m / 10).rounded()) * 10) m"
    }

    static func timeText(_ s: Double) -> String {
        let mins = max(1, Int((s / 60).rounded()))
        return mins >= 60 ? "\(mins / 60) hr \(mins % 60) min" : "\(mins) min"
    }

    // MARK: - HTTP

    private func post(_ url: String, body: [String: Any], fields: String,
                      done: @escaping ([String: Any]) -> Void) {
        call(url, body: body, fields: fields, done: done)
    }

    /// POST when there is a body, GET otherwise. quiet = don't show errors (used while typing).
    private func call(_ url: String, body: [String: Any]?, fields: String, quiet: Bool = false,
                      done: @escaping ([String: Any]) -> Void) {
        guard let u = URL(string: url) else { return }
        var req = URLRequest(url: u)
        req.httpMethod = body == nil ? "GET" : "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        req.setValue(fields, forHTTPHeaderField: "X-Goog-FieldMask")
        req.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        if let body { req.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            DispatchQueue.main.async {
                if quiet, err != nil || (resp as? HTTPURLResponse)?.statusCode != 200 { return }
                if let err {
                    self.routing = false
                    self.status = "No internet: \(err.localizedDescription)"
                } else if let code = (resp as? HTTPURLResponse)?.statusCode, code != 200 {
                    self.routing = false
                    let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(code)"
                    self.status = "Google error: \(msg)"
                } else {
                    done(json)
                }
            }
        }.resume()
    }
}
