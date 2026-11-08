import Foundation
import CoreLocation
import AVFoundation
import GoogleMaps

struct Place: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
}

struct Step {
    let instruction: String
    let maneuver: String
    let distance: Double
    let end: CLLocationCoordinate2D
}

/// Search, route and turn-by-turn logic using Google Places API (New) + Routes API.
final class NavModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    let apiKey: String

    @Published var location: CLLocation?
    @Published var results: [Place] = []
    @Published var destination: Place?
    @Published var path: GMSPath?
    @Published var steps: [Step] = []
    @Published var stepIndex = 0
    @Published var distanceToNext: Double = 0
    @Published var remainingMeters: Double = 0
    @Published var remainingSeconds: Double = 0
    @Published var status = ""
    @Published var voiceOn = true

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

    var navigating: Bool { destination != nil && !steps.isEmpty }

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

    // MARK: - Instruction text for screens

    var nextInstruction: String {
        guard navigating else { return "" }
        if stepIndex + 1 < steps.count { return steps[stepIndex + 1].instruction }
        return "Arrive at destination"
    }

    var nextManeuver: String {
        guard navigating, stepIndex + 1 < steps.count else { return "ARRIVE" }
        return steps[stepIndex + 1].maneuver
    }

    // MARK: - Location

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }
        location = loc
        if navigating { progress(loc) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        manager.startUpdatingLocation()
    }

    // MARK: - Search (Places API New)

    func search(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        status = "Searching…"
        var body: [String: Any] = ["textQuery": q, "pageSize": 8]
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
                return Place(name: name, address: p["formattedAddress"] as? String ?? "",
                             coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng))
            }
            self.status = self.results.isEmpty ? "Nothing found" : ""
        }
    }

    // MARK: - Route (Routes API)

    func start(to place: Place) {
        destination = place
        results = []
        route()
    }

    func stop() {
        destination = nil
        steps = []
        path = nil
        status = ""
        speech.stopSpeaking(at: .immediate)
    }

    private func route() {
        guard let dest = destination else { return }
        guard let here = location else { status = "Waiting for GPS…"; return }
        guard !routing else { return }
        routing = true
        lastReroute = Date()
        status = "Finding route…"
        func ll(_ c: CLLocationCoordinate2D) -> [String: Any] {
            ["location": ["latLng": ["latitude": c.latitude, "longitude": c.longitude]]]
        }
        let lang = Locale.preferredLanguages.first ?? "en"
        let body: [String: Any] = [
            "origin": ll(here.coordinate),
            "destination": ll(dest.coordinate),
            "travelMode": "DRIVE",
            "routingPreference": "TRAFFIC_AWARE",
            "languageCode": lang,
            "units": "METRIC",
        ]
        let fields = "routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline," +
            "routes.legs.steps.distanceMeters,routes.legs.steps.endLocation,routes.legs.steps.navigationInstruction"
        post("https://routes.googleapis.com/directions/v2:computeRoutes", body: body, fields: fields) { [weak self] json in
            guard let self else { return }
            self.routing = false
            guard self.destination != nil,
                  let r = (json["routes"] as? [[String: Any]])?.first,
                  let enc = (r["polyline"] as? [String: Any])?["encodedPolyline"] as? String else {
                if self.status == "Finding route…" { self.status = "No route found" }
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
            self.saidFar = false
            self.saidNear = false
            self.status = ""
            self.say(newSteps[0].instruction)
            if let l = self.location { self.progress(l) }
        }
    }

    // MARK: - Turn-by-turn

    private func progress(_ loc: CLLocation) {
        guard stepIndex < steps.count else { return }

        // Moved past the end of the current step → next step.
        var d = loc.distance(from: CLLocation(latitude: steps[stepIndex].end.latitude,
                                              longitude: steps[stepIndex].end.longitude))
        while d < 25, stepIndex < steps.count - 1 {
            stepIndex += 1
            saidFar = false
            saidNear = false
            d = loc.distance(from: CLLocation(latitude: steps[stepIndex].end.latitude,
                                              longitude: steps[stepIndex].end.longitude))
        }
        distanceToNext = d

        let after = steps.dropFirst(stepIndex + 1).reduce(0) { $0 + $1.distance }
        remainingMeters = d + after
        remainingSeconds = totalMeters > 0 ? totalSeconds * remainingMeters / totalMeters : 0

        // Arrived
        if stepIndex == steps.count - 1, d < 30 {
            say("You have arrived")
            stop()
            status = "Arrived ✅"
            return
        }

        // Voice prompts
        if !saidFar, d < 500, d > 200, steps[stepIndex].distance > 700 {
            saidFar = true
            say("In \(Self.distanceText(d)), \(nextInstruction)")
        }
        if !saidNear, d < 80 {
            saidNear = true
            saidFar = true
            say(nextInstruction)
        }

        // Off route → new route (at most every 10 s)
        if let p = path, Date().timeIntervalSince(lastReroute) > 10,
           !GMSGeometryIsLocationOnPathTolerance(loc.coordinate, p, true, 60) {
            status = "Re-routing…"
            route()
        }
    }

    private func say(_ text: String) {
        spokenText = text
        spokenId += 1
        guard voiceOn else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first)
        speech.speak(u)
    }

    static func distanceText(_ m: Double) -> String {
        if m >= 1000 { return String(format: "%.1f km", m / 1000) }
        if m >= 100 { return "\(Int((m / 50).rounded()) * 50) m" }
        return "\(Int((m / 10).rounded()) * 10) m"
    }

    static func timeText(_ s: Double) -> String {
        let mins = Int((s / 60).rounded())
        return mins >= 60 ? "\(mins / 60) h \(mins % 60) min" : "\(mins) min"
    }

    // MARK: - HTTP helper

    private func post(_ url: String, body: [String: Any], fields: String,
                      done: @escaping ([String: Any]) -> Void) {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        req.setValue(fields, forHTTPHeaderField: "X-Goog-FieldMask")
        req.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            DispatchQueue.main.async {
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
