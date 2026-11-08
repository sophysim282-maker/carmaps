import SwiftUI

private let navGreen = Color(red: 0.05, green: 0.47, blue: 0.27)
private let etaGreen = Color(red: 0.09, green: 0.55, blue: 0.27)

struct ContentView: View {
    @StateObject var nav: NavModel
    @ObservedObject var settings = Settings.shared
    @ObservedObject var maps = MapController.shared
    @StateObject private var car = CarLink()
    @State private var query = ""
    @State private var showSettings = false
    @State private var alertText: String?

    init(apiKey: String) { _nav = StateObject(wrappedValue: NavModel(apiKey: apiKey)) }

    var body: some View {
        ZStack {
            PhoneMap(nav: nav, settings: settings)
                .background(alignment: .topLeading) {
                    CarMap()
                        .frame(width: MapController.carSize.width, height: MapController.carSize.height)
                        .allowsHitTesting(false)
                }
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if nav.guiding { turnBanner } else { searchArea }
                Spacer()
                HStack(alignment: .bottom) {
                    leftPills
                    Spacer()
                    floatingButtons
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
                if nav.guiding {
                    guidingBar
                } else if let p = nav.selected {
                    placeSheet(p)
                }
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            car.start { [weak nav] in
                guard let nav else { return [:] }
                let s = Settings.shared
                return [
                    "navigating": nav.guiding,
                    "instruction": nav.nextInstruction,
                    "maneuver": nav.nextManeuver,
                    "distance": NavModel.distanceText(nav.distanceToNext),
                    "remaining": NavModel.distanceText(nav.remainingMeters),
                    "eta": NavModel.timeText(nav.remainingSeconds),
                    "arrival": nav.arrivalText,
                    "night": s.isNight,
                    "lang": s.language,
                    "spokenText": nav.spokenText,
                    "spokenId": nav.spokenId,
                ]
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView(settings: settings, car: car) }
        .alert(alertText ?? "", isPresented: Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Search (top)

    private var searchArea: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search here", text: $query)
                    .submitLabel(.search)
                    .onSubmit { nav.search(query) }
                    .onChange(of: query) { nav.autocomplete($0) }
                if !query.isEmpty {
                    Button { query = ""; nav.results = []; nav.suggestions = [] } label: {
                        Image(systemName: "xmark").foregroundColor(.secondary)
                    }
                }
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill").font(.title3).foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(Capsule().fill(Color(.systemBackground)).shadow(color: .black.opacity(0.2), radius: 6, y: 2))

            if !nav.suggestions.isEmpty { suggestionList } else if nav.results.isEmpty { chips } else { resultsList }

            if !nav.status.isEmpty {
                Text(nav.status).font(.footnote).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color(.systemBackground)).shadow(radius: 2))
            }
        }
        .padding(.horizontal)
        .padding(.top, 6)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("house.fill", "Home") { go(settings.home, "Home") }
                chip("briefcase.fill", "Work") { go(settings.work, "Work") }
                ForEach(settings.favorites) { p in
                    chip("star.fill", p.name) { nav.select(p) }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
    }

    private func chip(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundColor(.blue)
                Text(title).lineLimit(1)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color(.systemBackground)).shadow(color: .black.opacity(0.15), radius: 3, y: 1))
        }
        .foregroundColor(.primary)
    }

    private func go(_ p: Place?, _ label: String) {
        if let p { nav.select(p) } else { alertText = "Search a place, open it, then tap Save → Save as \(label)." }
    }

    private var suggestionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(nav.suggestions) { s in
                    Button { query = ""; nav.choose(s) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "mappin.circle.fill").font(.title2).foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.main).font(.headline).lineLimit(1)
                                Text(s.secondary).font(.caption).foregroundColor(.secondary).lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(12)
                    }
                    .foregroundColor(.primary)
                    Divider()
                }
            }
        }
        .frame(maxHeight: 340)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.systemBackground)).shadow(radius: 4))
    }

    private var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(nav.results) { p in
                    Button { query = ""; nav.select(p) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "mappin.circle.fill").font(.title2).foregroundColor(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.headline)
                                Text(p.address).font(.caption).foregroundColor(.secondary).lineLimit(2)
                            }
                            Spacer()
                        }
                        .padding(12)
                    }
                    .foregroundColor(.primary)
                    Divider()
                }
            }
        }
        .frame(maxHeight: 340)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.systemBackground)).shadow(radius: 4))
    }

    // MARK: - Place preview (bottom sheet)

    private func placeSheet(_ p: Place) -> some View {
        let saved = settings.isFavorite(p) || settings.home == p || settings.work == p
        return VStack(alignment: .leading, spacing: 12) {
            Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 40, height: 5).frame(maxWidth: .infinity)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.name).font(.title2.bold())
                    Text(p.address).font(.subheadline).foregroundColor(.secondary).lineLimit(2)
                }
                Spacer()
                Button { nav.clear() } label: {
                    Image(systemName: "xmark").font(.headline).padding(10)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
                .foregroundColor(.primary)
            }
            if !nav.steps.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "car.fill").foregroundColor(etaGreen)
                    Text(NavModel.timeText(nav.remainingSeconds)).font(.headline).foregroundColor(etaGreen)
                    Text("(\(NavModel.distanceText(nav.remainingMeters)))").foregroundColor(.secondary)
                }
            }
            HStack(spacing: 10) {
                Button {
                    maps.follow = true
                    nav.startGuidance()
                } label: {
                    Label("Start", systemImage: "location.north.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Capsule().fill(nav.steps.isEmpty ? Color.gray : Color.blue))
                        .foregroundColor(.white)
                }
                .disabled(nav.steps.isEmpty)

                Menu {
                    Button("Save as Home") { settings.home = p }
                    Button("Save as Work") { settings.work = p }
                    Button(settings.isFavorite(p) ? "Remove from Saved" : "Save to Saved ★") { settings.toggleFavorite(p) }
                } label: {
                    Label("Save", systemImage: saved ? "bookmark.fill" : "bookmark")
                        .font(.headline)
                        .padding(.vertical, 13)
                        .padding(.horizontal, 20)
                        .overlay(Capsule().stroke(Color.blue, lineWidth: 1.5))
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .background(RoundedRectangle(cornerRadius: 26).fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.2), radius: 10).ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Driving

    private var turnBanner: some View {
        HStack(spacing: 16) {
            Image(systemName: icon(nav.nextManeuver)).font(.system(size: 44, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                Text(NavModel.distanceText(nav.distanceToNext)).font(.system(size: 30, weight: .bold))
                Text(nav.nextInstruction).font(.title3.weight(.semibold)).lineLimit(2)
            }
            Spacer()
        }
        .foregroundColor(.white)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(navGreen).shadow(radius: 6))
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    private var guidingBar: some View {
        HStack(spacing: 14) {
            Button { nav.clear() } label: {
                Image(systemName: "xmark").font(.title3.bold()).foregroundColor(.white)
                    .frame(width: 50, height: 50).background(Circle().fill(Color.red))
            }
            VStack(spacing: 2) {
                Text(NavModel.timeText(nav.remainingSeconds)).font(.title2.bold()).foregroundColor(etaGreen)
                Text("\(NavModel.distanceText(nav.remainingMeters)) · \(nav.arrivalText)")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            Button { settings.voiceOn.toggle() } label: {
                Image(systemName: settings.voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.title3).frame(width: 50, height: 50)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .foregroundColor(.primary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 26).fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.2), radius: 10).ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Small buttons

    private var leftPills: some View {
        VStack(alignment: .leading, spacing: 8) {
            if nav.guiding && !maps.follow {
                Button { maps.recenter(nav) } label: {
                    Label("Re-centre", systemImage: "location.north.line.fill")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Capsule().fill(Color(.systemBackground)).shadow(radius: 3))
                }
                .foregroundColor(.blue)
            }
            Button { showSettings = true } label: {
                HStack(spacing: 6) {
                    Circle().fill(car.carConnected ? Color.green : Color.orange).frame(width: 9, height: 9)
                    Text(car.carConnected ? "Tesla connected" : "Tesla not connected")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(Color(.systemBackground)).shadow(radius: 3))
            }
            .foregroundColor(.primary)
        }
    }

    private var floatingButtons: some View {
        VStack(spacing: 12) {
            roundButton(settings.isNight ? "sun.max.fill" : "moon.fill") {
                settings.theme = settings.isNight ? "day" : "night"
            }
            roundButton(maps.follow ? "location.fill" : "location") { maps.recenter(nav) }
        }
    }

    private func roundButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3).foregroundColor(.blue)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Color(.systemBackground)).shadow(color: .black.opacity(0.2), radius: 4, y: 2))
        }
    }

    private func icon(_ m: String) -> String {
        switch m {
        case "TURN_LEFT", "TURN_SHARP_LEFT": return "arrow.turn.up.left"
        case "TURN_RIGHT", "TURN_SHARP_RIGHT": return "arrow.turn.up.right"
        case "TURN_SLIGHT_LEFT", "RAMP_LEFT", "FORK_LEFT": return "arrow.up.left"
        case "TURN_SLIGHT_RIGHT", "RAMP_RIGHT", "FORK_RIGHT": return "arrow.up.right"
        case "UTURN_LEFT", "UTURN_RIGHT": return "arrow.uturn.down"
        case "ROUNDABOUT_LEFT", "ROUNDABOUT_RIGHT", "ROUNDABOUT_CLOCKWISE", "ROUNDABOUT_COUNTERCLOCKWISE":
            return "arrow.triangle.2.circlepath"
        case "ARRIVE": return "flag.checkered"
        default: return "arrow.up"
        }
    }
}

// MARK: - Settings screen

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var car: CarLink
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Directions & voice") {
                    Picker("Language", selection: $settings.language) {
                        ForEach(Settings.languages, id: \.code) { Text($0.name).tag($0.code) }
                    }
                    Toggle("Voice guidance", isOn: $settings.voiceOn)
                    if !settings.voiceAvailable {
                        Text("Your iPhone has no voice for this language. Directions are shown as text. To add a voice: Settings → Accessibility → Spoken Content → Voices.")
                            .font(.footnote).foregroundColor(.orange)
                    }
                }
                Section("Map") {
                    Picker("Map colour", selection: $settings.theme) {
                        Text("Auto (night after 6 pm)").tag("auto")
                        Text("Day").tag("day")
                        Text("Night").tag("night")
                    }
                }
                Section("Saved places") {
                    savedRow("house.fill", "Home", settings.home) { settings.home = nil }
                    savedRow("briefcase.fill", "Work", settings.work) { settings.work = nil }
                    ForEach(settings.favorites) { p in
                        Label(p.name, systemImage: "star.fill")
                    }
                    .onDelete { settings.favorites.remove(atOffsets: $0) }
                }
                Section("Tesla") {
                    HStack {
                        Circle().fill(car.carConnected ? Color.green : Color.orange).frame(width: 10, height: 10)
                        Text(car.carConnected ? "Tesla connected" : "Tesla not connected")
                    }
                    ForEach(carAddresses(), id: \.self) { a in
                        Text(a).font(.body.monospaced().bold()).textSelection(.enabled)
                    }
                    Text("1. iPhone: Personal Hotspot ON\n2. Tesla: Wi-Fi → this iPhone\n3. Tesla browser: open the address above\nKeep this app open while driving.")
                        .font(.footnote).foregroundColor(.secondary)
                }
                Section("Google key") {
                    Button("Remove Google key", role: .destructive) {
                        UserDefaults.standard.removeObject(forKey: "googleKey")
                    }
                    Text("After removing, close the app fully and open it again to paste a new key.")
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func savedRow(_ icon: String, _ title: String, _ p: Place?, clear: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(p?.name ?? "Not set").foregroundColor(.secondary).lineLimit(1)
            if p != nil {
                Button(action: clear) { Image(systemName: "trash") }.buttonStyle(.borderless).foregroundColor(.red)
            }
        }
    }
}
