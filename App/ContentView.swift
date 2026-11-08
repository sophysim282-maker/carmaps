import SwiftUI

enum Theme {
    static let teal = Color(red: 0.04, green: 0.40, blue: 0.43)
    static let tealLight = Color(red: 0.84, green: 0.93, blue: 0.94)
    static let navBanner = Color(red: 0.05, green: 0.38, blue: 0.35)
    static let navBannerDark = Color(red: 0.03, green: 0.29, blue: 0.27)
    static let eta = Color(red: 0.09, green: 0.55, blue: 0.27)
}

func maneuverIcon(_ m: String) -> String {
    switch m {
    case "TURN_LEFT", "TURN_SHARP_LEFT": return "arrow.turn.up.left"
    case "TURN_RIGHT", "TURN_SHARP_RIGHT": return "arrow.turn.up.right"
    case "TURN_SLIGHT_LEFT", "RAMP_LEFT", "FORK_LEFT": return "arrow.up.left"
    case "TURN_SLIGHT_RIGHT", "RAMP_RIGHT", "FORK_RIGHT": return "arrow.up.right"
    case "UTURN_LEFT", "UTURN_RIGHT": return "arrow.uturn.down"
    case "ROUNDABOUT_LEFT", "ROUNDABOUT_RIGHT", "ROUNDABOUT_CLOCKWISE", "ROUNDABOUT_COUNTERCLOCKWISE":
        return "arrow.triangle.2.circlepath"
    case "ARRIVE": return "mappin.circle.fill"
    default: return "arrow.up"
    }
}

struct SheetBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.18), radius: 12, y: -2)
            .ignoresSafeArea(edges: .bottom)
    }
}

struct Grabber: View {
    var body: some View {
        Capsule().fill(Color.secondary.opacity(0.35)).frame(width: 40, height: 5).frame(maxWidth: .infinity)
    }
}

func circleIcon(_ name: String) -> some View {
    Image(systemName: name)
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(.primary)
        .frame(width: 40, height: 40)
        .background(Circle().fill(Color(.secondarySystemBackground)))
}

private let categories: [(icon: String, title: String, query: String)] = [
    ("fork.knife", "Restaurants", "restaurants"),
    ("cup.and.saucer.fill", "Coffee", "coffee"),
    ("fuelpump.fill", "Gas", "gas station"),
    ("bolt.fill", "Charging", "EV charging station"),
    ("bed.double.fill", "Hotels", "hotels"),
    ("cart.fill", "Groceries", "supermarket"),
]

struct ContentView: View {
    @StateObject var nav: NavModel
    @ObservedObject var settings = Settings.shared
    @ObservedObject var maps = MapController.shared
    @StateObject private var car = CarLink()
    @StateObject private var voice = VoiceSearch()
    @StateObject private var vpn = CarVPN()
    @State private var searchOpen = false
    @State private var voiceStart = false
    @State private var forDirections = false
    @State private var forStop = false
    @State private var showYou = false
    @State private var showSettings = false
    @State private var showLayers = false
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

            if nav.guiding {
                DriveOverlay(nav: nav, settings: settings, maps: maps)
            } else if nav.showingDirections, let p = nav.selected {
                DirectionsOverlay(nav: nav, settings: settings, place: p, addStop: { openSearch(stop: true) })
            } else {
                homeOverlay
            }

            if searchOpen {
                SearchScreen(nav: nav, settings: settings, voice: voice, isOpen: $searchOpen,
                             forDirections: $forDirections, forStop: $forStop, alertText: $alertText,
                             startWithVoice: voiceStart, openSettings: { showSettings = true })
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: searchOpen)
        .preferredColorScheme(settings.isNight ? .dark : .light)
        .onAppear(perform: startCar)
        .sheet(isPresented: $showYou) { YouSheet(nav: nav, settings: settings) }
        .sheet(isPresented: $showSettings) { SettingsView(settings: settings, car: car, vpn: vpn) }
        .sheet(isPresented: $showLayers) {
            LayersSheet(settings: settings).presentationDetents([.height(360)])
        }
        .alert(alertText ?? "", isPresented: Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func openSearch(voice: Bool = false, directions: Bool = false, stop: Bool = false) {
        voiceStart = voice
        forDirections = directions
        forStop = stop
        searchOpen = true
    }

    // MARK: - Home

    private var homeOverlay: some View {
        VStack(spacing: 0) {
            searchPill
                .padding(.horizontal)
                .padding(.top, 6)
            categoryChips
                .padding(.top, 10)
            HStack {
                if !nav.status.isEmpty {
                    Text(nav.status).font(.footnote).lineLimit(3)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color(.systemBackground)).shadow(radius: 2))
                }
                Spacer()
                Button { showLayers = true } label: { floatingIcon("square.2.layers.3d", size: 46) }
            }
            .padding(.horizontal)
            .padding(.top, 10)
            Spacer()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    if let t = nav.weatherTemp {
                        HStack(spacing: 6) {
                            Image(systemName: nav.weatherIcon).symbolRenderingMode(.multicolor)
                            Text(t).fontWeight(.semibold)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(Color(.systemBackground)).shadow(radius: 3))
                    }
                    carPill
                }
                Spacer()
                VStack(spacing: 14) {
                    Button { maps.recenter(nav) } label: {
                        floatingIcon(maps.follow ? "location.fill" : "location", size: 58)
                    }
                    if nav.selected == nil && nav.results.isEmpty {
                        Button { openSearch(directions: true) } label: {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(RoundedRectangle(cornerRadius: 18).fill(Theme.teal).shadow(radius: 4))
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)

            if let p = nav.selected {
                PlaceCard(nav: nav, settings: settings, place: p)
            } else if !nav.results.isEmpty {
                ResultsSheet(nav: nav)
            } else {
                tabBar
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tab("mappin.and.ellipse", "Explore", selected: true) {}
            tab("bookmark", "You", selected: false) { showYou = true }
            tab("gearshape", "Settings", selected: false) { showSettings = true }
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
        .background(Color(.systemBackground).shadow(color: .black.opacity(0.08), radius: 4, y: -2).ignoresSafeArea(edges: .bottom))
    }

    private func tab(_ icon: String, _ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .medium))
                    .frame(width: 64, height: 32)
                    .background(Capsule().fill(selected ? Theme.tealLight : Color.clear))
                Text(title).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(selected ? Theme.teal : .secondary)
        }
    }

    private var searchPill: some View {
        HStack(spacing: 12) {
            Button { openSearch() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse").font(.title3).foregroundColor(.red)
                    Text("Search here").font(.title3).foregroundColor(.secondary)
                    Spacer()
                }
            }
            Button { openSearch(voice: true) } label: {
                Image(systemName: "mic.fill").font(.title3).foregroundColor(.primary)
            }
            Button { showSettings = true } label: {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 34)).foregroundColor(Theme.teal)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .frame(height: 58)
        .background(Capsule().fill(Color(.systemBackground)).shadow(color: .black.opacity(0.2), radius: 6, y: 2))
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.title) { c in
                    Button { nav.search(c.query) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: c.icon)
                            Text(c.title)
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color(.systemBackground)).shadow(color: .black.opacity(0.15), radius: 3, y: 1))
                    }
                    .foregroundColor(.primary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }

    private var carPill: some View {
        Button { showSettings = true } label: {
            HStack(spacing: 6) {
                Circle().fill(car.carConnected ? Color.green : Color.orange).frame(width: 9, height: 9)
                Text(car.carConnected ? "Tesla connected" : (vpn.isOn ? "Tesla: \(CarVPN.address):8080" : "Tesla link off"))
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(Color(.systemBackground)).shadow(radius: 3))
        }
        .foregroundColor(.primary)
    }

    private func floatingIcon(_ name: String, size: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.4, weight: .medium))
            .foregroundColor(Theme.teal)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(.systemBackground)).shadow(color: .black.opacity(0.2), radius: 4, y: 2))
    }

    // MARK: - Tesla link

    private func startCar() {
        UIApplication.shared.isIdleTimerDisabled = true
        vpn.turnOn()   // gives the iPhone the address 240.3.3.3 for the Tesla
        let nav = self.nav
        car.nav = nav
        car.server.onCommand = { [weak nav] action, params in nav?.handleCar(action, params) }
        car.start { [weak nav] in nav?.carState() ?? [:] }
    }
}
