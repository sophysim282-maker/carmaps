import SwiftUI
import GoogleMaps

private let routeBlue = UIColor(red: 0.10, green: 0.45, blue: 0.91, alpha: 1)
private let routeBlueDark = UIColor(red: 0.05, green: 0.28, blue: 0.68, alpha: 1)
private let altFill = UIColor(red: 0.69, green: 0.76, blue: 0.85, alpha: 1)
private let altEdge = UIColor(red: 0.47, green: 0.55, blue: 0.66, alpha: 1)

/// Two Google maps: the iPhone map and a wide (16:10) map only for the Tesla screen.
final class MapController: NSObject, ObservableObject, GMSMapViewDelegate {
    static let shared = MapController()
    static let carSize = CGSize(width: 800, height: 500)

    @Published var follow = true
    @Published var headingUp = true
    @Published var carFollow = true
    private var carZoom: Float = 17
    weak var nav: NavModel?

    let phoneMap: GMSMapView
    let carMap: GMSMapView

    private final class Layer {
        let map: GMSMapView
        var lines: [GMSPolyline] = []
        var bubbles: [GMSMarker] = []
        var pins: [GMSMarker] = []
        let dest = GMSMarker()
        let arrow = GMSMarker()
        init(_ map: GMSMapView) {
            self.map = map
            arrow.icon = MapController.arrowImage
            arrow.groundAnchor = CGPoint(x: 0.5, y: 0.5)
            arrow.isFlat = true
            arrow.zIndex = 100
            dest.zIndex = 50
        }
    }

    private var phone: Layer!
    private var car: Layer!
    private var layers: [Layer] { [phone, car] }
    private var shownRoutes = -1
    private var shownResults: [Place] = []
    private var night: Bool?
    private var mapType: String?
    private var traffic: Bool?
    private var hadFix = false
    private var wasGuiding = false

    override init() {
        let cam = GMSCameraPosition(latitude: 11.5564, longitude: 104.9282, zoom: 12)
        phoneMap = GMSMapView(frame: .zero, camera: cam)
        carMap = GMSMapView(frame: CGRect(origin: .zero, size: Self.carSize), camera: cam)
        super.init()
        phone = Layer(phoneMap)
        car = Layer(carMap)
        for m in [phoneMap, carMap] {
            m.isMyLocationEnabled = true
            m.settings.myLocationButton = false
            m.isBuildingsEnabled = true
            m.settings.rotateGestures = true
            m.settings.tiltGestures = true
        }
        carMap.settings.setAllGesturesEnabled(false)
        phoneMap.settings.compassButton = false
        phoneMap.delegate = self
    }

    // MARK: - Taps

    func mapView(_ mapView: GMSMapView, didTap overlay: GMSOverlay) {
        if let i = overlay.userData as? Int { nav?.selectRoute(i) }
    }

    func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
        if let p = marker.userData as? Place { nav?.select(p); return true }
        if let i = marker.userData as? Int { nav?.selectRoute(i); return true }
        return marker == phone.dest
    }

    func mapView(_ mapView: GMSMapView, didLongPressAt coordinate: CLLocationCoordinate2D) {
        guard let nav, !nav.guiding else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        nav.dropPin(coordinate)
    }

    func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
        if gesture && follow { DispatchQueue.main.async { self.follow = false } }
    }

    // When not driving, the Tesla shows the same place as the iPhone.
    func mapView(_ mapView: GMSMapView, didChange position: GMSCameraPosition) {
        if !wasGuiding { carMap.camera = position }
    }

    // MARK: - Update from app state

    func update(nav: NavModel, settings: Settings) {
        self.nav = nav

        if night != settings.isNight {
            night = settings.isNight
            let style = settings.isNight ? (try? GMSMapStyle(jsonString: nightStyle)) : nil
            phoneMap.mapStyle = style
            carMap.mapStyle = style
        }
        if mapType != settings.mapType {
            mapType = settings.mapType
            let t: GMSMapViewType = settings.mapType == "satellite" ? .hybrid : .normal
            phoneMap.mapType = t
            carMap.mapType = t
        }
        if traffic != settings.traffic {
            traffic = settings.traffic
            phoneMap.isTrafficEnabled = settings.traffic
            carMap.isTrafficEnabled = settings.traffic
        }

        if shownResults != nav.results {
            shownResults = nav.results
            for l in layers { drawPins(l, nav.results) }
            if !nav.results.isEmpty {
                var b = GMSCoordinateBounds()
                for p in nav.results { b = b.includingCoordinate(p.coordinate) }
                phoneMap.animate(with: GMSCameraUpdate.fit(b, with: UIEdgeInsets(top: 150, left: 50, bottom: 380, right: 50)))
            }
        }

        if shownRoutes != nav.routesVersion {
            shownRoutes = nav.routesVersion
            for l in layers { drawRoutes(l, nav) }
            if !nav.guiding, !nav.routes.isEmpty { overview(nav) }
        }

        for l in layers {
            if let s = nav.selected {
                l.dest.position = s.coordinate
                l.dest.title = s.name
                if l.dest.map == nil { l.dest.map = l.map }
            } else {
                l.dest.map = nil
            }
            l.map.isMyLocationEnabled = !nav.guiding
            if nav.guiding, let c = nav.carCoordinate {
                l.arrow.position = c
                l.arrow.rotation = nav.carBearing
                if l.arrow.map == nil { l.arrow.map = l.map }
            } else {
                l.arrow.map = nil
            }
        }

        if nav.guiding {
            phoneMap.padding = UIEdgeInsets(top: 330, left: 0, bottom: 120, right: 0)
        } else if nav.showingDirections {
            phoneMap.padding = UIEdgeInsets(top: 130, left: 0, bottom: 360, right: 0)
        } else {
            phoneMap.padding = UIEdgeInsets(top: 130, left: 0, bottom: nav.selected == nil ? 20 : 300, right: 0)
        }

        if wasGuiding && !nav.guiding { carMap.camera = phoneMap.camera; follow = true; carFollow = true }
        if !wasGuiding && nav.guiding { follow = true; carFollow = true }
        wasGuiding = nav.guiding

        guard let loc = nav.location else { return }
        if !hadFix {
            hadFix = true
            phoneMap.camera = GMSCameraPosition(target: loc.coordinate, zoom: 16)
        }
        if nav.guiding, let c = nav.carCoordinate {
            let bearing = headingUp ? nav.carBearing : 0
            if follow {
                phoneMap.animate(to: GMSCameraPosition(target: c, zoom: 18, bearing: bearing, viewingAngle: headingUp ? 60 : 0))
            }
            if carFollow {
                carMap.animate(to: GMSCameraPosition(target: c, zoom: carZoom, bearing: bearing, viewingAngle: headingUp ? 55 : 0))
            }
        }
    }

    // MARK: - Buttons

    func recenter(_ nav: NavModel) {
        follow = true
        carFollow = true
        if !nav.guiding, let loc = nav.location {
            phoneMap.animate(to: GMSCameraPosition(target: loc.coordinate, zoom: 16.5))
        }
    }

    func overview(_ nav: NavModel) {
        guard !nav.routes.isEmpty else { return }
        if nav.guiding { follow = false; carFollow = false }
        var b = GMSCoordinateBounds()
        for r in nav.routes { b = b.includingPath(r.path) }
        if let c = nav.carCoordinate { b = b.includingCoordinate(c) }
        phoneMap.animate(with: GMSCameraUpdate.fit(b, with: UIEdgeInsets(top: 60, left: 50, bottom: 60, right: 50)))
        carMap.animate(with: GMSCameraUpdate.fit(b, withPadding: 60))
    }

    // MARK: - Control from the Tesla screen

    func zoom(_ d: Float, guiding: Bool) {
        if guiding {
            carZoom = max(12, min(20, carZoom + d))
            if !carFollow { carMap.animate(toZoom: carMap.camera.zoom + d) }
        } else {
            phoneMap.animate(toZoom: phoneMap.camera.zoom + d)
        }
    }

    /// fx, fy = how far the finger moved, as a part of the car map width/height.
    func pan(fx: Double, fy: Double, guiding: Bool) {
        let w = Double(carMap.bounds.width), h = Double(carMap.bounds.height)
        let target = carMap.projection.coordinate(for: CGPoint(x: w / 2 - fx * w, y: h / 2 - fy * h))
        if guiding {
            carFollow = false
            carMap.moveCamera(GMSCameraUpdate.setTarget(target))
        } else {
            follow = false
            phoneMap.moveCamera(GMSCameraUpdate.setTarget(target))
        }
    }

    func carCoordinate(fx: Double, fy: Double) -> CLLocationCoordinate2D {
        carMap.projection.coordinate(for: CGPoint(x: fx * Double(carMap.bounds.width), y: fy * Double(carMap.bounds.height)))
    }

    // MARK: - Drawing

    private func drawPins(_ l: Layer, _ places: [Place]) {
        l.pins.forEach { $0.map = nil }
        l.pins = places.map { p in
            let m = GMSMarker(position: p.coordinate)
            m.title = p.name
            m.userData = p
            m.map = l.map
            return m
        }
    }

    private func drawRoutes(_ l: Layer, _ nav: NavModel) {
        l.lines.forEach { $0.map = nil }
        l.bubbles.forEach { $0.map = nil }
        l.lines = []
        l.bubbles = []
        let order = nav.routes.indices.filter { $0 != nav.routeIndex }
            + (nav.routes.indices.contains(nav.routeIndex) ? [nav.routeIndex] : [])
        for i in order {
            let r = nav.routes[i]
            let sel = i == nav.routeIndex
            let edge = GMSPolyline(path: r.path)
            edge.strokeWidth = sel ? 11 : 9
            edge.strokeColor = sel ? routeBlueDark : altEdge
            edge.zIndex = sel ? 12 : 2
            let fill = GMSPolyline(path: r.path)
            fill.strokeWidth = sel ? 7.5 : 5.5
            fill.strokeColor = sel ? routeBlue : altFill
            fill.zIndex = sel ? 13 : 3
            for line in [edge, fill] {
                line.isTappable = true
                line.userData = i
                line.map = l.map
                l.lines.append(line)
            }
            if !nav.guiding {
                let mid = r.path.coordinate(at: r.path.count() / 2)
                let b = GMSMarker(position: mid)
                b.icon = Self.bubble(NavModel.timeText(r.seconds), selected: sel)
                b.groundAnchor = CGPoint(x: 0.5, y: 1)
                b.userData = i
                b.zIndex = sel ? 40 : 30
                b.map = l.map
                l.bubbles.append(b)
            }
        }
    }

    static func bubble(_ text: String, selected: Bool) -> UIImage {
        let font = UIFont.systemFont(ofSize: 15, weight: .bold)
        let size = (text as NSString).size(withAttributes: [.font: font])
        let w = ceil(size.width) + 20, h = ceil(size.height) + 10
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h + 7)).image { _ in
            let bg: UIColor = selected ? routeBlue : .white
            let shape = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: 7)
            shape.move(to: CGPoint(x: w / 2 - 7, y: h))
            shape.addLine(to: CGPoint(x: w / 2, y: h + 7))
            shape.addLine(to: CGPoint(x: w / 2 + 7, y: h))
            bg.setFill()
            shape.fill()
            if !selected {
                UIColor(white: 0.75, alpha: 1).setStroke()
                shape.lineWidth = 1
                shape.stroke()
            }
            (text as NSString).draw(at: CGPoint(x: 10, y: 5),
                                    withAttributes: [.font: font, .foregroundColor: selected ? UIColor.white : UIColor.black])
        }
    }

    /// Blue navigation arrow with white edge.
    static let arrowImage: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48)).image { ctx in
            let c = ctx.cgContext
            c.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor.black.withAlphaComponent(0.4).cgColor)
            let p = UIBezierPath()
            p.move(to: CGPoint(x: 24, y: 4))
            p.addLine(to: CGPoint(x: 41, y: 42))
            p.addLine(to: CGPoint(x: 24, y: 33))
            p.addLine(to: CGPoint(x: 7, y: 42))
            p.close()
            p.lineJoinStyle = .round
            p.lineWidth = 4
            UIColor.white.setStroke()
            p.stroke()
            routeBlue.setFill()
            p.fill()
        }
    }()
}

struct PhoneMap: UIViewRepresentable {
    @ObservedObject var nav: NavModel
    @ObservedObject var settings: Settings

    func makeUIView(context: Context) -> GMSMapView { MapController.shared.phoneMap }
    func updateUIView(_ uiView: GMSMapView, context: Context) {
        MapController.shared.update(nav: nav, settings: settings)
    }
}

/// Sits behind the phone map (never seen on the phone). Pictures of it go to the Tesla.
struct CarMap: UIViewRepresentable {
    func makeUIView(context: Context) -> GMSMapView { MapController.shared.carMap }
    func updateUIView(_ uiView: GMSMapView, context: Context) {}
}

private let nightStyle = """
[{"elementType":"geometry","stylers":[{"color":"#242f3e"}]},
{"elementType":"labels.text.stroke","stylers":[{"color":"#242f3e"}]},
{"elementType":"labels.text.fill","stylers":[{"color":"#8a8f99"}]},
{"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},
{"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#263c3f"}]},
{"featureType":"road","elementType":"geometry","stylers":[{"color":"#38414e"}]},
{"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#212a37"}]},
{"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9ca5b3"}]},
{"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#746855"}]},
{"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#1f2835"}]},
{"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#f3d19c"}]},
{"featureType":"transit","elementType":"geometry","stylers":[{"color":"#2f3948"}]},
{"featureType":"water","elementType":"geometry","stylers":[{"color":"#17263c"}]},
{"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#515c6d"}]}]
"""
