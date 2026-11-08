import SwiftUI

// MARK: - Place card (bottom sheet)

struct PlaceCard: View {
    @ObservedObject var nav: NavModel
    @ObservedObject var settings: Settings
    @ObservedObject var maps = MapController.shared
    let place: Place
    @Environment(\.openURL) private var openURL

    private var shareURL: URL {
        URL(string: "https://www.google.com/maps/search/?api=1&query=\(place.lat),\(place.lng)")!
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grabber()
            HStack(alignment: .top, spacing: 10) {
                Text(place.name).font(.title2.weight(.semibold)).lineLimit(2)
                Spacer()
                ShareLink(item: shareURL) { circleIcon("square.and.arrow.up") }
                Button { nav.clear() } label: { circleIcon("xmark") }
            }
            infoLines
            buttonsRow
            photos
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(SheetBackground())
    }

    private var driveTime: String {
        guard let s = nav.modeSeconds["DRIVE"] else { return "…" }
        return s < 0 ? "—" : NavModel.timeText(s)
    }

    private var infoLines: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let r = nav.info?.rating {
                    Text(String(format: "%.1f", r))
                    Stars(rating: r)
                    if let c = nav.info?.ratingCount { Text("(\(c))").foregroundColor(.secondary) }
                    Text("·").foregroundColor(.secondary)
                } else if nav.info != nil {
                    Text("No reviews").foregroundColor(.secondary)
                    Text("·").foregroundColor(.secondary)
                }
                Image(systemName: "car.fill").font(.caption).foregroundColor(.secondary)
                Text(driveTime).foregroundColor(.secondary)
            }
            .font(.subheadline)
            if let t = nav.info?.type {
                Text(t).font(.subheadline).foregroundColor(.secondary)
            }
            if nav.info?.type == nil || place.placeId == nil {
                Text(place.address).font(.subheadline).foregroundColor(.secondary).lineLimit(2)
            }
            if let open = nav.info?.openNow {
                HStack(spacing: 4) {
                    Text(open ? "Open" : "Closed").foregroundColor(open ? Theme.eta : .red)
                    if let h = nav.info?.hoursText { Text("· \(h)").foregroundColor(.secondary) }
                }
                .font(.subheadline)
            }
        }
    }

    private var buttonsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { nav.openDirections() } label: {
                    PillLabel(title: "Directions", icon: "arrow.triangle.turn.up.right.diamond.fill", filled: true)
                }
                Button { maps.follow = true; nav.startGuidance() } label: {
                    PillLabel(title: "Start", icon: "location.north.fill", filled: false)
                }
                .disabled(nav.routes.isEmpty)
                if let phone = nav.info?.phone {
                    Button {
                        let digits = phone.filter { "+0123456789".contains($0) }
                        if let u = URL(string: "tel:\(digits)") { openURL(u) }
                    } label: { PillLabel(title: "Call", icon: "phone.fill", filled: false) }
                }
                SaveMenu(settings: settings, place: place)
            }
        }
    }

    @ViewBuilder private var photos: some View {
        if let list = nav.info?.photos, !list.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(list, id: \.self) { url in
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFill()
                            } else {
                                Color.gray.opacity(0.2)
                            }
                        }
                        .frame(width: 230, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
    }
}

struct Stars: View {
    let rating: Double
    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { i in
                let v = rating - Double(i)
                Image(systemName: v >= 0.75 ? "star.fill" : (v >= 0.25 ? "star.leadinghalf.filled" : "star"))
            }
        }
        .font(.caption2)
        .foregroundColor(.orange)
    }
}

struct PillLabel: View {
    let title: String
    let icon: String
    let filled: Bool
    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Capsule().fill(filled ? Theme.teal : Theme.tealLight))
            .foregroundColor(filled ? .white : Theme.teal)
    }
}

struct SaveMenu: View {
    @ObservedObject var settings: Settings
    let place: Place
    var body: some View {
        Menu {
            Button("Save as Home") { settings.home = place }
            Button("Save as Work") { settings.work = place }
            Button(settings.isFavorite(place) ? "Remove from Saved" : "Save to Saved ★") { settings.toggleFavorite(place) }
        } label: {
            let saved = settings.isFavorite(place) || place.same(settings.home) || place.same(settings.work)
            PillLabel(title: saved ? "Saved" : "Save", icon: saved ? "bookmark.fill" : "bookmark", filled: false)
        }
    }
}

// MARK: - Search results list

struct ResultsSheet: View {
    @ObservedObject var nav: NavModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grabber()
            HStack {
                Text("Results").font(.title3.weight(.semibold))
                Spacer()
                Button { nav.results = [] } label: { circleIcon("xmark") }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(nav.results) { p in
                        Button { nav.select(p) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "mappin.circle.fill").font(.title2).foregroundColor(.red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.headline).lineLimit(1)
                                    Text(p.address).font(.caption).foregroundColor(.secondary).lineLimit(2)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 10)
                        }
                        .foregroundColor(.primary)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .background(SheetBackground())
    }
}

// MARK: - Search screen

struct SearchScreen: View {
    @ObservedObject var nav: NavModel
    @ObservedObject var settings: Settings
    @ObservedObject var voice: VoiceSearch
    @Binding var isOpen: Bool
    @Binding var forDirections: Bool
    @Binding var alertText: String?
    let startWithVoice: Bool
    let openSettings: () -> Void
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: close) {
                    Image(systemName: "chevron.left").font(.title3.weight(.semibold))
                }
                .foregroundColor(.primary)
                TextField(forDirections ? "Choose destination" : "Search here", text: $query)
                    .font(.title3)
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit(submit)
                    .onChange(of: query) { nav.autocomplete($0) }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark") }.foregroundColor(.secondary)
                }
                Button(action: listen) {
                    Image(systemName: voice.listening ? "waveform" : "mic.fill").font(.title3)
                }
                .foregroundColor(voice.listening ? .red : .primary)
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(Capsule().fill(Color(.secondarySystemBackground)))
            .padding(.horizontal)
            .padding(.top, 8)

            if voice.listening {
                Text(voice.text.isEmpty ? "Listening…" : voice.text)
                    .font(.title2).foregroundColor(Theme.teal).padding()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if query.isEmpty {
                        shortcuts
                        Rectangle().fill(Color(.secondarySystemBackground)).frame(height: 8)
                        if !settings.recents.isEmpty {
                            Text("Recent").font(.headline).padding(.horizontal).padding(.top, 16).padding(.bottom, 4)
                        }
                        ForEach(settings.recents) { p in
                            row(icon: "clock", title: p.name, subtitle: p.address) { pick(p) }
                        }
                    } else {
                        row(icon: "magnifyingglass", title: "Search “\(query)”", subtitle: "", action: submit)
                        ForEach(nav.suggestions) { s in
                            row(icon: "mappin", title: s.main, subtitle: s.secondary) {
                                let dir = forDirections
                                nav.choose(s) { _ in if dir { nav.openDirections() } }
                                close()
                            }
                        }
                    }
                }
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .onAppear {
            if startWithVoice { listen() } else { focused = true }
        }
    }

    private var shortcuts: some View {
        HStack(spacing: 10) {
            shortcut("house.fill", "Home", settings.home?.address ?? "Set location") { pick(settings.home, "Home") }
            shortcut("briefcase.fill", "Work", settings.work?.address ?? "Set location") { pick(settings.work, "Work") }
            shortcut("ellipsis", "More", "") { close(); openSettings() }
        }
        .padding()
    }

    private func shortcut(_ icon: String, _ title: String, _ sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(Theme.teal)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Theme.tealLight))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    if !sub.isEmpty { Text(sub).font(.caption).foregroundColor(.secondary).lineLimit(1) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundColor(.primary)
    }

    private func row(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body).lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .foregroundColor(.primary)
    }

    private func pick(_ p: Place?, _ label: String = "") {
        guard let p else {
            alertText = "Search a place, open it, then tap Save → Save as \(label)."
            return
        }
        nav.select(p)
        if forDirections { nav.openDirections() }
        close()
    }

    private func submit() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        nav.search(query)
        close()
    }

    private func listen() {
        voice.start(language: settings.language) { text in
            query = text
            submit()
        }
    }

    private func close() {
        if voice.listening { voice.stop() }
        nav.suggestions = []
        isOpen = false
        forDirections = false
    }
}

// MARK: - Directions (route preview)

struct DirectionsOverlay: View {
    @ObservedObject var nav: NavModel
    @ObservedObject var settings: Settings
    @ObservedObject var maps = MapController.shared
    let place: Place

    private var shareURL: URL {
        URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(place.lat),\(place.lng)")!
    }

    var body: some View {
        VStack(spacing: 0) {
            topCard
            Spacer()
            sheet
        }
    }

    private var topCard: some View {
        HStack(spacing: 12) {
            Button { nav.showingDirections = false } label: {
                Image(systemName: "chevron.left").font(.title3.weight(.semibold))
            }
            .foregroundColor(.primary)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Circle().fill(Color.blue).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    Text("Your location").foregroundColor(.blue)
                }
                .padding(.vertical, 10)
                Divider().padding(.leading, 24)
                HStack(spacing: 12) {
                    Image(systemName: "mappin").foregroundColor(.red).frame(width: 12)
                    Text(place.name).lineLimit(1)
                }
                .padding(.vertical, 10)
            }
            .font(.body)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color(.systemBackground)).shadow(color: .black.opacity(0.2), radius: 6, y: 2))
        .padding(.horizontal)
        .padding(.top, 6)
    }

    private var modeTitle: String {
        switch nav.mode {
        case "TWO_WHEELER": return "Motorbike"
        case "WALK": return "Walk"
        default: return "Drive"
        }
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grabber()
            HStack(spacing: 10) {
                Text(modeTitle).font(.title.weight(.semibold))
                Spacer()
                Menu {
                    Toggle("Avoid tolls", isOn: binding(\.avoidTolls))
                    Toggle("Avoid highways", isOn: binding(\.avoidHighways))
                    Toggle("Avoid ferries", isOn: binding(\.avoidFerries))
                } label: { circleIcon("slider.horizontal.3") }
                ShareLink(item: shareURL) { circleIcon("square.and.arrow.up") }
                Button { nav.clear() } label: { circleIcon("xmark") }
            }
            HStack(spacing: 24) {
                modeTab("car.fill", "DRIVE")
                modeTab("scooter", "TWO_WHEELER")
                modeTab("figure.walk", "WALK")
                Spacer()
            }
            Divider()
            if nav.mode != "WALK" { avoidChips }
            routeList
            HStack(spacing: 10) {
                Button { maps.follow = true; nav.startGuidance() } label: {
                    PillLabel(title: "Start", icon: "location.north.fill", filled: true)
                }
                .disabled(nav.routes.isEmpty)
                SaveMenu(settings: settings, place: place)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(SheetBackground())
    }

    private func binding(_ key: ReferenceWritableKeyPath<Settings, Bool>) -> Binding<Bool> {
        Binding(get: { settings[keyPath: key] },
                set: { settings[keyPath: key] = $0; nav.refreshRoutes() })
    }

    private func modeTab(_ icon: String, _ m: String) -> some View {
        let sel = nav.mode == m
        let t = nav.modeSeconds[m].map { $0 < 0 ? "—" : NavModel.timeText($0) } ?? "…"
        return Button { nav.setMode(m) } label: {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                    Text(t)
                }
                .font(.headline)
                Rectangle().fill(sel ? Theme.teal : Color.clear).frame(height: 3)
            }
            .fixedSize()
            .foregroundColor(sel ? Theme.teal : .secondary)
        }
    }

    private var avoidChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                avoidChip("Avoid tolls", \.avoidTolls)
                avoidChip("Avoid highways", \.avoidHighways)
                avoidChip("Avoid ferries", \.avoidFerries)
            }
        }
    }

    private func avoidChip(_ title: String, _ key: ReferenceWritableKeyPath<Settings, Bool>) -> some View {
        let on = settings[keyPath: key]
        return Button {
            settings[keyPath: key].toggle()
            nav.refreshRoutes()
        } label: {
            HStack(spacing: 6) {
                if on { Image(systemName: "checkmark") }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10).fill(on ? Theme.tealLight : Color(.secondarySystemBackground)))
            .foregroundColor(on ? Theme.teal : .primary)
        }
    }

    private var routeList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if nav.routes.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(nav.status.isEmpty ? "Finding routes…" : nav.status).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                ForEach(Array(nav.routes.enumerated()), id: \.offset) { i, r in
                    Button { nav.selectRoute(i) } label: { routeRow(i, r) }.foregroundColor(.primary)
                }
            }
        }
        .frame(maxHeight: 170)
    }

    private func routeRow(_ i: Int, _ r: RouteOption) -> some View {
        let sel = i == nav.routeIndex
        var tag = ""
        if i == 0 { tag = " · Best route" } else if r.labels.contains("SHORTER_DISTANCE") { tag = " · Shorter" }
        return HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 2).fill(sel ? Theme.teal : Color.clear).frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(NavModel.timeText(r.seconds)).font(.title3.bold()).foregroundColor(i == 0 ? Theme.eta : .primary)
                Text("Arrive \(NavModel.clock(r.seconds))\(tag)").font(.subheadline).foregroundColor(.secondary)
                Text(NavModel.distanceText(r.meters)).font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Driving screen

struct DriveOverlay: View {
    @ObservedObject var nav: NavModel
    @ObservedObject var settings: Settings
    @ObservedObject var maps: MapController

    private var dark: Bool { settings.darkControls }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                banner
                if let t = nav.thenManeuver {
                    HStack(spacing: 8) {
                        Text("Then")
                        Image(systemName: maneuverIcon(t))
                    }
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.navBannerDark))
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            HStack {
                if !nav.status.isEmpty {
                    Text(nav.status).font(.footnote)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color(.systemBackground)))
                }
                Spacer()
                VStack(spacing: 14) {
                    navButton(maps.headingUp ? "location.north.line.fill" : "safari") { maps.headingUp.toggle() }
                    navButton(settings.voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill") { settings.voiceOn.toggle() }
                    navButton("arrow.triangle.branch") { maps.overview(nav) }
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)

            Spacer()

            HStack {
                if !maps.follow {
                    Button { maps.recenter(nav) } label: {
                        Label("Re-centre", systemImage: "location.north.fill")
                            .font(.title3.weight(.semibold))
                            .padding(.horizontal, 22).padding(.vertical, 14)
                            .background(Capsule().fill(dark ? Color.black.opacity(0.85) : Color(.systemBackground)).shadow(radius: 4))
                            .foregroundColor(dark ? .white : Theme.teal)
                    }
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 10)

            bottomBar
        }
    }

    private var banner: some View {
        HStack(spacing: 18) {
            Image(systemName: maneuverIcon(nav.nextManeuver)).font(.system(size: 44, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                Text(NavModel.distanceText(nav.distanceToNext)).font(.system(size: 30, weight: .bold))
                Text(nav.nextInstruction).font(.system(size: 22, weight: .medium)).lineLimit(2)
            }
            Spacer()
        }
        .foregroundColor(.white)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 22).fill(Theme.navBanner).shadow(radius: 6))
    }

    private func navButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(dark ? .white : .primary)
                .frame(width: 58, height: 58)
                .background(Circle().fill(dark ? Color.black.opacity(0.85) : Color(.systemBackground)).shadow(radius: 4))
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NavModel.timeText(nav.remainingSeconds))
                    .font(.system(size: 34, weight: .bold)).foregroundColor(Theme.eta)
                Text("\(NavModel.distanceText(nav.remainingMeters)) · \(nav.arrivalText)")
                    .font(.title3).foregroundColor(.secondary)
            }
            Spacer()
            Button { nav.clear() } label: {
                Text("Exit").font(.title3.weight(.semibold)).foregroundColor(.white)
                    .padding(.horizontal, 30).padding(.vertical, 14)
                    .background(Capsule().fill(Color.red))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .background(SheetBackground())
    }
}

// MARK: - Layers

struct LayersSheet: View {
    @ObservedObject var settings: Settings
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Map type").font(.headline)
            HStack(spacing: 18) {
                tile("Default", "map.fill", "normal")
                tile("Satellite", "globe.asia.australia.fill", "satellite")
                Spacer()
            }
            Toggle("Traffic", isOn: $settings.traffic)
            Picker("Colour", selection: $settings.theme) {
                Text("Auto").tag("auto")
                Text("Day").tag("day")
                Text("Night").tag("night")
            }
            .pickerStyle(.segmented)
        }
        .padding(24)
    }

    private func tile(_ title: String, _ icon: String, _ value: String) -> some View {
        let sel = settings.mapType == value
        return Button { settings.mapType = value } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 28))
                    .frame(width: 76, height: 64)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(sel ? Theme.teal : Color.clear, lineWidth: 3))
                Text(title).font(.subheadline)
            }
            .foregroundColor(sel ? Theme.teal : .primary)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var car: CarLink
    @ObservedObject var vpn: CarVPN
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
                Section("Route options") {
                    Toggle("Avoid tolls", isOn: $settings.avoidTolls)
                    Toggle("Avoid highways", isOn: $settings.avoidHighways)
                    Toggle("Avoid ferries", isOn: $settings.avoidFerries)
                }
                Section("Map") {
                    Picker("Map type", selection: $settings.mapType) {
                        Text("Default").tag("normal")
                        Text("Satellite").tag("satellite")
                    }
                    Toggle("Traffic", isOn: $settings.traffic)
                    Picker("Colour", selection: $settings.theme) {
                        Text("Auto (night after 6 pm)").tag("auto")
                        Text("Day").tag("day")
                        Text("Night").tag("night")
                    }
                }
                Section("Saved places") {
                    savedRow("house.fill", "Home", settings.home) { settings.home = nil }
                    savedRow("briefcase.fill", "Work", settings.work) { settings.work = nil }
                    ForEach(settings.favorites) { p in Label(p.name, systemImage: "star.fill") }
                        .onDelete { settings.favorites.remove(atOffsets: $0) }
                    if !settings.recents.isEmpty {
                        Button("Clear recent searches", role: .destructive) { settings.recents = [] }
                    }
                }
                Section("Tesla") {
                    Toggle(isOn: Binding(get: { vpn.isOn }, set: { $0 ? vpn.turnOn() : vpn.turnOff() })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tesla link (\(CarVPN.address))")
                            Text(vpn.statusText).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    if let e = vpn.error { Text(e).font(.footnote).foregroundColor(.red) }
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
