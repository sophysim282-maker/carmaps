import Foundation
import UIKit

/// The Tesla screen can control the app: this builds what the car shows and runs what the car taps.
extension NavModel {
    func carState() -> [String: Any] {
        let s = settings
        let screen: String
        if guiding { screen = "drive" }
        else if showingDirections && selected != nil { screen = "directions" }
        else if selected != nil { screen = "place" }
        else if !results.isEmpty { screen = "results" }
        else { screen = "home" }

        var d: [String: Any] = [
            "screen": screen,
            "navigating": guiding,
            "instruction": nextInstruction,
            "maneuver": nextManeuver,
            "then": thenManeuver ?? "",
            "distance": NavModel.distanceText(distanceToNext),
            "remaining": NavModel.distanceText(remainingMeters),
            "eta": NavModel.timeText(remainingSeconds),
            "arrival": arrivalText,
            "weather": weatherTemp ?? "",
            "night": s.isNight,
            "lang": s.language,
            "spokenText": spokenText,
            "spokenId": spokenId,
            "status": status,
            "mapType": s.mapType,
            "follow": MapController.shared.carFollow,
            "home": s.home?.name ?? "",
            "work": s.work?.name ?? "",
            "favorites": s.favorites.map { ["name": $0.name] },
            "recents": s.recents.prefix(8).map { ["name": $0.name, "address": $0.address] },
            "results": results.map { ["name": $0.name, "address": $0.address] },
            "suggestions": suggestions.map { ["id": $0.id, "main": $0.main, "secondary": $0.secondary] },
            "mode": mode,
            "stop": stop?.name ?? "",
            "heading": carBearing,
            "bg": UIApplication.shared.applicationState != .active,
            "headingUp": MapController.shared.headingUp,
            "driveResults": driveResults.map { ["name": $0.name, "address": $0.address] },
            "modes": modeSeconds.mapValues { $0 < 0 ? "—" : NavModel.timeText($0) },
            "routes": routes.enumerated().map { i, r in
                ["time": NavModel.timeText(r.seconds), "arrive": NavModel.clock(r.seconds),
                 "dist": NavModel.distanceText(r.meters), "sel": i == routeIndex] as [String: Any]
            },
        ]
        if let p = selected {
            var pl: [String: Any] = ["name": p.name, "address": p.address]
            if let i = info {
                if let r = i.rating { pl["rating"] = r; pl["count"] = i.ratingCount ?? 0 }
                if let t = i.type { pl["type"] = t }
                if let o = i.openNow { pl["open"] = o }
                if let h = i.hoursText { pl["hours"] = h }
            }
            if let sec = modeSeconds["DRIVE"], sec >= 0 { pl["drive"] = NavModel.timeText(sec) }
            d["place"] = pl
        }
        return d
    }

    func handleCar(_ a: String, _ p: [String: String]) {
        let maps = MapController.shared
        let s = settings
        let i = Int(p["i"] ?? "") ?? -1
        let fx = Double(p["x"] ?? "") ?? 0
        let fy = Double(p["y"] ?? "") ?? 0
        switch a {
        case "search": search(p["q"] ?? "")
        case "type": autocomplete(p["q"] ?? "")
        case "suggest": if let sg = suggestions.first(where: { $0.id == p["id"] }) { choose(sg) }
        case "result": if results.indices.contains(i) { select(results[i]) }
        case "recent": if s.recents.indices.contains(i) { select(s.recents[i]) }
        case "fav": if s.favorites.indices.contains(i) { select(s.favorites[i]) }
        case "home": if let h = s.home { select(h) }
        case "work": if let w = s.work { select(w) }
        case "directions": openDirections()
        case "back": if showingDirections { showingDirections = false } else { clear() }
        case "close": clear(); results = []
        case "route": selectRoute(i)
        case "mode": setMode(p["m"] ?? "DRIVE")
        case "start":
            maps.follow = true
            maps.carFollow = true
            startGuidance()
        case "exit": clear()
        case "recenter": maps.recenter(self)
        case "overview": maps.overview(self)
        case "zoom": maps.zoom(Float(p["d"] ?? "") ?? 1, guiding: guiding)
        case "pan": maps.pan(fx: fx, fy: fy, guiding: guiding)
        case "pin": if !guiding { dropPin(maps.carCoordinate(fx: fx, fy: fy)) }
        case "layer": s.mapType = s.mapType == "satellite" ? "normal" : "satellite"
        case "stopsuggest": if let sg = suggestions.first(where: { $0.id == p["id"] }) { chooseStop(sg) }
        case "removestop": removeStop()
        case "compass": maps.headingUp.toggle()
        case "navsearch": searchWhileDriving(p["q"] ?? "")
        case "go": if driveResults.indices.contains(i) { goNow(driveResults[i]) }
        case "clearnear": driveResults = []; maps.recenter(self)
        default: break
        }
    }
}
