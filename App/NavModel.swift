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

struct RouteOption: Identifiable {
    let id: Int
    let path: GMSPath
    let steps: [Step]
    let meters: Double
    let seconds: Double
    let labels: [String]
}

struct PlaceInfo {
    var rating: Double?
    var ratingCount: Int?
    var type: String?
    var openNow: Bool?
    var hoursText: String?
    var phone: String?
    var photos: [URL] = []
}

/// Search, place details, routes and turn-by-turn guidance.
final class NavModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    let api: GoogleAPI
    let settings = Settings.shared

    @Published var location: CLLocation?
    @Published var carCoordinate: CLLocationCoordinate2D?
    @Published var carBearing: Double = 0

    @Published var results: [Place] = []
    @Published var suggestions: [Suggestion] = []
    @Published var selected: Place?
    @Published var info: PlaceInfo?

    @Published var showingDirections = false
    @Published var mode = "DRIVE"
    @Published var modeSeconds: [String: Double] = [:]
    @Published var routes: [RouteOption] = []
    @Published var routeIndex = 0
    @Published var routesVersion = 0
    @Published var stop: Place?
    /// Search results shown while driving (tap one to go there instead).
    @Published var driveResults: [Place] = []
    private var pendingStart = false

    @Published var guiding = false
    @Published var stepIndex = 0
    @Published var distanceToNext: Double = 0
    @Published var remainingMeters: Double = 0
    @Published var remainingSeconds: Double = 0

    @Published var status = ""
    @Published var weatherTemp: String?
    @Published var weatherIcon = "cloud.sun.fill"

    private(set) var spokenText = ""
    private(set) var spokenId = 0

    private let manager = CLLocationManager()
    private let speech = AVSpeechSynthesizer()
    private var saidFar = false
    private var saidNear = false
    private var lastReroute = Date.distantPast
    private var routing = false
    private var sessionToken = UUID().uuidString
    private var autoWork: DispatchWorkItem?
    private var lastWeather = Date.distantPast

    var route: RouteOption? { routes.indices.contains(routeIndex) ? routes[routeIndex] : nil }
    var steps: [Step] { route?.steps ?? [] }
    var path: GMSPath? { route?.path }

    init(apiKey: String) {
        api = GoogleAPI(key: apiKey)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        Self.voiceAudio()
    }

    static func voiceAudio() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt,
                                                         options: [.duckOthers, .mixWithOthers])
    }

    // MARK: - Text for screens

    var nextInstruction: String {
        guard guiding, !steps.isEmpty else { return "" }
        if stepIndex + 1 < steps.count { return steps[stepIndex + 1].instruction }
        return "Arrive at \(selected?.name ?? "destination")"
    }

    var nextManeuver: String {
        guard guiding, stepIndex + 1 < steps.count else { return "ARRIVE" }
        return steps[stepIndex + 1].maneuver
    }

    /// The turn after the next one, when it comes quickly (shown as "Then ↱").
    var thenManeuver: String? {
        guard guiding, stepIndex + 2 < steps.count, steps[stepIndex + 1].distance < 400 else { return nil }
        return steps[stepIndex + 2].maneuver
    }

    static func clock(_ seconds: Double) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: Date().addingTimeInterval(seconds))
    }

    var arrivalText: String { Self.clock(remainingSeconds) }

    // MARK: - Location

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }
        let first = location == nil
        location = loc
        if guiding {
            progress(loc)
        } else {
            carCoordinate = loc.coordinate
            if loc.course >= 0 { carBearing = loc.course }
        }
        if first, selected != nil, routes.isEmpty { fetchRoutes() }
        if Date().timeIntervalSince(lastWeather) > 900 { loadWeather(loc.coordinate) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        manager.startUpdatingLocation()
    }

    // MARK: - Search

    private func bias() -> [String: Any]? {
        guard let l = location else { return nil }
        return ["circle": ["center": ["latitude": l.coordinate.latitude, "longitude": l.coordinate.longitude],
                           "radius": 30000.0]]
    }

    func search(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        autoWork?.cancel()
        suggestions = []
        clear()
        status = "Searching…"
        var body: [String: Any] = ["textQuery": q, "pageSize": 12, "languageCode": settings.language]
        if let b = bias() { body["locationBias"] = b }
        api.call("https://places.googleapis.com/v1/places:searchText", body: body,
                 fields: "places.id,places.displayName,places.formattedAddress,places.location") { [weak self] json, err in
            guard let self else { return }
            if let err { self.status = err; return }
            let places = (json?["places"] as? [[String: Any]]) ?? []
            self.results = places.compactMap { p in
                guard let loc = p["location"] as? [String: Any],
                      let lat = loc["latitude"] as? Double, let lng = loc["longitude"] as? Double else { return nil }
                let name = (p["displayName"] as? [String: Any])?["text"] as? String ?? "Place"
                return Place(name: name, address: p["formattedAddress"] as? String ?? "", lat: lat, lng: lng,
                             placeId: p["id"] as? String)
            }
            self.status = self.results.isEmpty ? "Nothing found" : ""
        }
    }

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
        if let b = bias() { body["locationBias"] = b }
        api.call("https://places.googleapis.com/v1/places:autocomplete", body: body,
                 fields: "suggestions.placePrediction.placeId,suggestions.placePrediction.structuredFormat,suggestions.placePrediction.text") { [weak self] json, err in
            guard let self, err == nil else { return }
            let list = (json?["suggestions"] as? [[String: Any]]) ?? []
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

    func choose(_ s: Suggestion, selectIt: Bool = true, then: ((Place) -> Void)? = nil) {
        autoWork?.cancel()
        suggestions = []
        status = "Loading…"
        let url = "https://places.googleapis.com/v1/places/\(s.id)?languageCode=\(settings.language)&sessionToken=\(sessionToken)"
        sessionToken = UUID().uuidString
        api.call(url, fields: "id,displayName,formattedAddress,location") { [weak self] json, err in
            guard let self else { return }
            guard let loc = json?["location"] as? [String: Any],
                  let lat = loc["latitude"] as? Double, let lng = loc["longitude"] as? Double else {
                self.status = err ?? "Could not open this place"
                return
            }
            let name = (json?["displayName"] as? [String: Any])?["text"] as? String ?? s.main
            self.status = ""
            let p = Place(name: name, address: json?["formattedAddress"] as? String ?? s.secondary,
                          lat: lat, lng: lng, placeId: s.id)
            if selectIt { self.select(p) }
            then?(p)
        }
    }

    /// Long-press on the map → "Dropped pin" with its address (Geocoding API).
    func dropPin(_ c: CLLocationCoordinate2D) {
        let pin = Place(name: "Dropped pin", address: String(format: "%.5f, %.5f", c.latitude, c.longitude),
                        lat: c.latitude, lng: c.longitude)
        select(pin, remember: false)
        let url = "https://maps.googleapis.com/maps/api/geocode/json?latlng=\(c.latitude),\(c.longitude)&language=\(settings.language)&key=\(api.key)"
        api.call(url) { [weak self] json, _ in
            guard let self, self.selected.map({ pin.same($0) }) == true,
                  let addr = (json?["results"] as? [[String: Any]])?.first?["formatted_address"] as? String else { return }
            self.selected?.address = addr
        }
    }

    // MARK: - Place card

    func select(_ place: Place, remember: Bool = true) {
        endGuidance()
        selected = place
        info = nil
        results = []
        driveResults = []
        stop = nil
        showingDirections = false
        routes = []
        routeIndex = 0
        modeSeconds = [:]
        routesVersion += 1
        if remember { settings.addRecent(place) }
        loadDetails(place)
        fetchRoutes()
        fetchModeTimes()
    }

    private func loadDetails(_ place: Place) {
        guard let id = place.placeId else { return }
        let fields = "rating,userRatingCount,primaryTypeDisplayName,currentOpeningHours.openNow," +
            "currentOpeningHours.nextOpenTime,currentOpeningHours.nextCloseTime,nationalPhoneNumber,internationalPhoneNumber,photos"
        api.call("https://places.googleapis.com/v1/places/\(id)?languageCode=\(settings.language)", fields: fields) { [weak self] json, _ in
            guard let self, let json, place.same(self.selected) else { return }
            var i = PlaceInfo()
            i.rating = json["rating"] as? Double
            i.ratingCount = json["userRatingCount"] as? Int
            i.type = (json["primaryTypeDisplayName"] as? [String: Any])?["text"] as? String
            i.phone = json["internationalPhoneNumber"] as? String ?? json["nationalPhoneNumber"] as? String
            if let h = json["currentOpeningHours"] as? [String: Any] {
                i.openNow = h["openNow"] as? Bool
                let f = DateFormatter()
                f.dateFormat = "h a"
                if i.openNow == true, let t = Self.date(h["nextCloseTime"]) {
                    i.hoursText = "Closes \(f.string(from: t))"
                } else if i.openNow == false, let t = Self.date(h["nextOpenTime"]) {
                    i.hoursText = "Opens \(f.string(from: t))"
                }
            }
            let photos = (json["photos"] as? [[String: Any]]) ?? []
            i.photos = photos.prefix(8).compactMap { ($0["name"] as? String).flatMap { self.api.photoURL($0) } }
            self.info = i
        }
    }

    private static func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    // MARK: - Stops and searching while driving

    func setStop(_ p: Place) {
        stop = p
        routes = []
        routesVersion += 1
        fetchRoutes()
        fetchModeTimes()
    }

    func chooseStop(_ s: Suggestion) {
        choose(s, selectIt: false) { [weak self] p in self?.setStop(p) }
    }

    func removeStop() {
        stop = nil
        routes = []
        routesVersion += 1
        fetchRoutes()
        fetchModeTimes()
    }

    /// Search near you without stopping navigation (gas, coffee…).
    func searchWhileDriving(_ q: String) {
        var body: [String: Any] = ["textQuery": q, "pageSize": 8, "languageCode": settings.language]
        if let b = bias() { body["locationBias"] = b }
        status = "Searching…"
        api.call("https://places.googleapis.com/v1/places:searchText", body: body,
                 fields: "places.id,places.displayName,places.formattedAddress,places.location") { [weak self] json, err in
            guard let self else { return }
            self.status = err ?? ""
            let places = (json?["places"] as? [[String: Any]]) ?? []
            self.driveResults = places.compactMap { p in
                guard let loc = p["location"] as? [String: Any],
                      let lat = loc["latitude"] as? Double, let lng = loc["longitude"] as? Double else { return nil }
                let name = (p["displayName"] as? [String: Any])?["text"] as? String ?? "Place"
                return Place(name: name, address: p["formattedAddress"] as? String ?? "", lat: lat, lng: lng,
                             placeId: p["id"] as? String)
            }
            if self.driveResults.isEmpty && err == nil { self.status = "Nothing found nearby" }
        }
    }

    /// Drive to this place now (from results found while driving).
    func goNow(_ p: Place) {
        mode = "DRIVE"
        select(p)
        pendingStart = true
    }

    // MARK: - Routes

    func openDirections() {
        showingDirections = true
        if routes.isEmpty { fetchRoutes() }
    }

    func setMode(_ m: String) {
        guard m != mode else { return }
        mode = m
        routes = []
        routesVersion += 1
        fetchRoutes()
    }

    func refreshRoutes() {
        fetchRoutes()
        fetchModeTimes()
    }

    func selectRoute(_ i: Int) {
        guard !guiding, routes.indices.contains(i) else { return }
        routeIndex = i
        remainingMeters = routes[i].meters
        remainingSeconds = routes[i].seconds
        routesVersion += 1
    }

    private func ll(_ c: CLLocationCoordinate2D) -> [String: Any] {
        ["location": ["latLng": ["latitude": c.latitude, "longitude": c.longitude]]]
    }

    private func routeBody(_ m: String, alternatives: Bool, from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> [String: Any] {
        var b: [String: Any] = [
            "origin": ll(from), "destination": ll(to), "travelMode": m,
            "languageCode": settings.language, "units": "METRIC",
            "computeAlternativeRoutes": alternatives && stop == nil,
        ]
        if let st = stop, m != "TRANSIT" { b["intermediates"] = [ll(st.coordinate)] }
        if m == "DRIVE" || m == "TWO_WHEELER" {
            b["routingPreference"] = "TRAFFIC_AWARE"
            b["routeModifiers"] = ["avoidTolls": settings.avoidTolls, "avoidHighways": settings.avoidHighways,
                                   "avoidFerries": settings.avoidFerries]
        }
        return b
    }

    private static func seconds(_ v: Any?) -> Double { Double(String((v as? String ?? "0s").dropLast())) ?? 0 }

    /// Times for Car / Motorbike / Walk tabs.
    private func fetchModeTimes() {
        guard let dest = selected, let here = location else { return }
        for m in ["DRIVE", "TWO_WHEELER", "TRANSIT", "WALK"] {
            api.call("https://routes.googleapis.com/directions/v2:computeRoutes",
                     body: routeBody(m, alternatives: false, from: here.coordinate, to: dest.coordinate),
                     fields: "routes.duration") { [weak self] json, _ in
                guard let self, dest.same(self.selected) else { return }
                let r = (json?["routes"] as? [[String: Any]])?.first
                self.modeSeconds[m] = r.map { Self.seconds($0["duration"]) } ?? -1
            }
        }
    }

    private func fetchRoutes() {
        guard let dest = selected else { return }
        guard let here = location else { status = "Waiting for GPS…"; return }
        guard !routing else { return }
        routing = true
        lastReroute = Date()
        if guiding { status = "Re-routing…" }
        let fields = "routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline,routes.routeLabels," +
            "routes.legs.steps.distanceMeters,routes.legs.steps.endLocation,routes.legs.steps.navigationInstruction"
        let wantMode = mode
        api.call("https://routes.googleapis.com/directions/v2:computeRoutes",
                 body: routeBody(mode, alternatives: !guiding, from: here.coordinate, to: dest.coordinate),
                 fields: fields) { [weak self] json, err in
            guard let self else { return }
            self.routing = false
            guard dest.same(self.selected), wantMode == self.mode else { return }
            if let err { self.status = err; return }
            let raw = (json?["routes"] as? [[String: Any]]) ?? []
            let parsed: [RouteOption] = raw.enumerated().compactMap { i, r in
                guard let enc = (r["polyline"] as? [String: Any])?["encodedPolyline"] as? String,
                      let path = GMSPath(fromEncodedPath: enc) else { return nil }
                var steps: [Step] = []
                for leg in (r["legs"] as? [[String: Any]]) ?? [] {
                    for s in (leg["steps"] as? [[String: Any]]) ?? [] {
                        let ni = s["navigationInstruction"] as? [String: Any]
                        let end = ((s["endLocation"] as? [String: Any])?["latLng"] as? [String: Any]) ?? [:]
                        steps.append(Step(
                            instruction: (ni?["instructions"] as? String ?? "Continue").replacingOccurrences(of: "\n", with: " "),
                            maneuver: ni?["maneuver"] as? String ?? "STRAIGHT",
                            distance: Double(s["distanceMeters"] as? Int ?? 0),
                            end: CLLocationCoordinate2D(latitude: end["latitude"] as? Double ?? 0,
                                                        longitude: end["longitude"] as? Double ?? 0)))
                    }
                }
                guard !steps.isEmpty else { return nil }
                return RouteOption(id: i, path: path, steps: steps, meters: Double(r["distanceMeters"] as? Int ?? 0),
                                   seconds: Self.seconds(r["duration"]), labels: r["routeLabels"] as? [String] ?? [])
            }
            guard let first = parsed.first else { self.status = "No route found"; return }
            self.routes = parsed
            self.routeIndex = 0
            self.remainingMeters = first.meters
            self.remainingSeconds = first.seconds
            self.modeSeconds[wantMode] = first.seconds
            self.routesVersion += 1
            self.status = ""
            if self.pendingStart {
                self.pendingStart = false
                self.startGuidance()
                return
            }
            if self.guiding {
                self.stepIndex = 0
                self.saidFar = false
                self.saidNear = false
                if let l = self.location { self.progress(l) }
            }
        }
    }

    // MARK: - Guidance

    func startGuidance() {
        guard let r = route else { return }
        routes = [r]
        routeIndex = 0
        routesVersion += 1
        guiding = true
        showingDirections = false
        stepIndex = 0
        saidFar = false
        saidNear = false
        lastReroute = Date()
        say(r.steps[0].instruction)
        if let l = location { progress(l) }
    }

    func endGuidance() {
        guiding = false
        speech.stopSpeaking(at: .immediate)
    }

    func clear() {
        endGuidance()
        selected = nil
        info = nil
        showingDirections = false
        routes = []
        routesVersion += 1
        status = ""
    }

    private func progress(_ loc: CLLocation) {
        guard let r = route, stepIndex < r.steps.count else { return }

        // Keep the arrow on the route (free "snap to road").
        if let s = Self.snap(loc.coordinate, to: r.path), s.distance < 30 {
            carCoordinate = s.coordinate
            carBearing = s.bearing
        } else {
            carCoordinate = loc.coordinate
            if loc.course >= 0 { carBearing = loc.course }
        }

        func dist(_ i: Int) -> Double {
            loc.distance(from: CLLocation(latitude: r.steps[i].end.latitude, longitude: r.steps[i].end.longitude))
        }
        var d = dist(stepIndex)
        while d < 25, stepIndex < r.steps.count - 1 {
            stepIndex += 1
            saidFar = false
            saidNear = false
            d = dist(stepIndex)
        }
        distanceToNext = d

        let after = r.steps.dropFirst(stepIndex + 1).reduce(0) { $0 + $1.distance }
        remainingMeters = d + after
        remainingSeconds = r.meters > 0 ? r.seconds * remainingMeters / r.meters : 0

        if stepIndex == r.steps.count - 1, d < 30 {
            say(settings.language == "en" ? "You have arrived" : nextInstruction)
            clear()
            status = "Arrived ✅"
            return
        }

        if !saidFar, d < 500, d > 200, r.steps[stepIndex].distance > 700 {
            saidFar = true
            say(settings.language == "en" ? "In \(Self.distanceText(d)), \(nextInstruction)" : nextInstruction)
        }
        if !saidNear, d < 80 {
            saidNear = true
            saidFar = true
            say(nextInstruction)
        }

        if Date().timeIntervalSince(lastReroute) > 10,
           !GMSGeometryIsLocationOnPathTolerance(loc.coordinate, r.path, true, 50) {
            fetchRoutes()
        }
    }

    /// Nearest point on the route and the road direction there.
    static func snap(_ c: CLLocationCoordinate2D, to path: GMSPath)
        -> (coordinate: CLLocationCoordinate2D, bearing: Double, distance: Double)? {
        let n = Int(path.count())
        guard n >= 2 else { return nil }
        let lat0 = c.latitude, lng0 = c.longitude
        let kx = cos(lat0 * .pi / 180) * 111_320.0
        let ky = 110_540.0
        var best: (d: Double, x: Double, y: Double, b: Double)?
        for i in 0..<(n - 1) {
            let a = path.coordinate(at: UInt(i))
            let b = path.coordinate(at: UInt(i + 1))
            let ax = (a.longitude - lng0) * kx, ay = (a.latitude - lat0) * ky
            let dx = (b.longitude - lng0) * kx - ax, dy = (b.latitude - lat0) * ky - ay
            let len2 = dx * dx + dy * dy
            let t = len2 > 0 ? max(0, min(1, -(ax * dx + ay * dy) / len2)) : 0
            let px = ax + t * dx, py = ay + t * dy
            let d = (px * px + py * py).squareRoot()
            if best == nil || d < best!.d {
                var brg = atan2(dx, dy) * 180 / .pi
                if brg < 0 { brg += 360 }
                best = (d, px, py, brg)
            }
        }
        guard let b = best else { return nil }
        return (CLLocationCoordinate2D(latitude: lat0 + b.y / ky, longitude: lng0 + b.x / kx), b.b, b.d)
    }

    private func say(_ text: String) {
        spokenText = text
        spokenId += 1
        guard settings.voiceOn else { return }
        Self.voiceAudio()
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = settings.voice
        speech.speak(u)
    }

    // MARK: - Weather (Weather API)

    private func loadWeather(_ c: CLLocationCoordinate2D) {
        lastWeather = Date()
        let url = "https://weather.googleapis.com/v1/currentConditions:lookup?key=\(api.key)" +
            "&location.latitude=\(c.latitude)&location.longitude=\(c.longitude)"
        api.call(url) { [weak self] json, _ in
            guard let self, let json else { return }
            if let t = (json["temperature"] as? [String: Any])?["degrees"] as? Double {
                self.weatherTemp = "\(Int(t.rounded()))°"
            }
            let type = ((json["weatherCondition"] as? [String: Any])?["type"] as? String ?? "").uppercased()
            let day = json["isDaytime"] as? Bool ?? true
            if type.contains("THUNDER") { self.weatherIcon = "cloud.bolt.rain.fill" }
            else if type.contains("RAIN") || type.contains("SHOWER") { self.weatherIcon = "cloud.rain.fill" }
            else if type.contains("PARTLY") || type.contains("MOSTLY") { self.weatherIcon = day ? "cloud.sun.fill" : "cloud.moon.fill" }
            else if type.contains("CLOUD") { self.weatherIcon = "cloud.fill" }
            else if type.contains("CLEAR") { self.weatherIcon = day ? "sun.max.fill" : "moon.stars.fill" }
        }
    }

    // MARK: - Formatting

    static func distanceText(_ m: Double) -> String {
        if m >= 1000 { return String(format: "%.1f km", m / 1000) }
        if m >= 100 { return "\(Int((m / 50).rounded()) * 50) m" }
        return "\(Int((m / 10).rounded()) * 10) m"
    }

    static func timeText(_ s: Double) -> String {
        let mins = max(1, Int((s / 60).rounded()))
        return mins >= 60 ? "\(mins / 60) hr \(mins % 60) min" : "\(mins) min"
    }
}
