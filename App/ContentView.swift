import SwiftUI

struct ContentView: View {
    @StateObject var nav: NavModel
    @StateObject private var car = CarLink()
    @State private var query = ""
    @State private var showCarHelp = false

    init(apiKey: String) { _nav = StateObject(wrappedValue: NavModel(apiKey: apiKey)) }

    var body: some View {
        ZStack {
            MapView(nav: nav).ignoresSafeArea()

            VStack(spacing: 10) {
                if nav.navigating { turnBanner } else { searchBar }
                if !nav.results.isEmpty { resultsList }
                if !nav.status.isEmpty {
                    Text(nav.status).font(.footnote).padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                Spacer()
                bottomBar
            }
            .padding()
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            car.start { [weak nav] in
                guard let nav else { return [:] }
                return [
                    "navigating": nav.navigating,
                    "instruction": nav.nextInstruction,
                    "maneuver": nav.nextManeuver,
                    "distance": NavModel.distanceText(nav.distanceToNext),
                    "remaining": NavModel.distanceText(nav.remainingMeters),
                    "eta": NavModel.timeText(nav.remainingSeconds),
                    "spokenText": nav.spokenText,
                    "spokenId": nav.spokenId,
                ]
            }
        }
        .sheet(isPresented: $showCarHelp) { carHelp }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("Where to?", text: $query)
                .submitLabel(.search)
                .onSubmit { nav.search(query) }
            if !query.isEmpty {
                Button { query = ""; nav.results = [] } label: { Image(systemName: "xmark.circle.fill") }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(nav.results) { p in
                    Button { nav.start(to: p); query = ""; MapHolder.shared.follow = true } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.headline)
                            Text(p.address).font(.caption).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                    .foregroundColor(.primary)
                    Divider()
                }
            }
        }
        .frame(maxHeight: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var turnBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: icon(nav.nextManeuver)).font(.system(size: 40, weight: .bold))
            VStack(alignment: .leading) {
                Text(NavModel.distanceText(nav.distanceToNext)).font(.title.bold())
                Text(nav.nextInstruction).font(.headline).lineLimit(2)
            }
            Spacer()
        }
        .foregroundColor(.white)
        .padding()
        .background(Color(red: 0.04, green: 0.42, blue: 0.23), in: RoundedRectangle(cornerRadius: 16))
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if nav.navigating {
                HStack {
                    VStack(alignment: .leading) {
                        Text(NavModel.timeText(nav.remainingSeconds)).font(.title2.bold())
                        Text("\(NavModel.distanceText(nav.remainingMeters)) · \(nav.destination?.name ?? "")")
                            .font(.caption).lineLimit(1)
                    }
                    Spacer()
                    Button { nav.voiceOn.toggle() } label: {
                        Image(systemName: nav.voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }
                    .buttonStyle(.bordered)
                    Button("Re-center") { MapHolder.shared.follow = true }.buttonStyle(.bordered)
                    Button("Stop", role: .destructive) { nav.stop() }.buttonStyle(.borderedProminent)
                }
            }
            Button { showCarHelp = true } label: {
                HStack {
                    Circle().fill(car.carConnected ? Color.green : Color.orange).frame(width: 10, height: 10)
                    Text(car.carConnected ? "Car connected" : "Car not connected: tap for help")
                    Spacer()
                    Text("172.20.10.1:8080").font(.caption.monospaced())
                }
            }
            .foregroundColor(.primary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var carHelp: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect the Tesla").font(.title.bold())
            Text("1. iPhone: Settings → Personal Hotspot → ON")
            Text("2. Tesla: Wi-Fi → choose this iPhone")
            Text("3. Tesla browser: open")
            ForEach(carAddresses(), id: \.self) { Text($0).font(.title3.monospaced().bold()).textSelection(.enabled) }
            Text("Keep this app open on the iPhone while driving.").foregroundColor(.secondary)
            Spacer()
        }
        .padding()
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
