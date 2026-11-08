import SwiftUI
import GoogleMaps

/// Two Google maps: one for the iPhone, one wide (16:10) map only for the Tesla screen.
final class MapController: NSObject, ObservableObject, GMSMapViewDelegate {
    static let shared = MapController()
    static let carSize = CGSize(width: 800, height: 500)

    @Published var follow = true

    let phoneMap: GMSMapView
    let carMap: GMSMapView
    private let phoneLine = GMSPolyline()
    private let carLine = GMSPolyline()
    private let phoneDest = GMSMarker()
    private let carDest = GMSMarker()
    private var lastPath: GMSPath?
    private var night: Bool?
    private var hadFix = false
    private var wasGuiding = false

    override init() {
        let cam = GMSCameraPosition(latitude: 11.5564, longitude: 104.9282, zoom: 12)
        phoneMap = GMSMapView(frame: .zero, camera: cam)
        carMap = GMSMapView(frame: CGRect(origin: .zero, size: Self.carSize), camera: cam)
        super.init()
        for m in [phoneMap, carMap] {
            m.isMyLocationEnabled = true
            m.settings.myLocationButton = false
            m.isTrafficEnabled = true
            m.isBuildingsEnabled = true
        }
        carMap.settings.setAllGesturesEnabled(false)
        phoneMap.settings.compassButton = true
        phoneMap.delegate = self
        let blue = UIColor(red: 0.10, green: 0.45, blue: 0.91, alpha: 1)
        phoneLine.strokeWidth = 7
        carLine.strokeWidth = 9
        phoneLine.strokeColor = blue
        carLine.strokeColor = blue
    }

    // User dragged the phone map → stop following.
    func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
        if gesture && follow { DispatchQueue.main.async { self.follow = false } }
    }

    // When not driving, the car shows the same place as the phone.
    func mapView(_ mapView: GMSMapView, didChange position: GMSCameraPosition) {
        if !wasGuiding { carMap.camera = position }
    }

    func update(nav: NavModel, night isNight: Bool) {
        if night != isNight {
            night = isNight
            let style = isNight ? (try? GMSMapStyle(jsonString: nightStyle)) : nil
            phoneMap.mapStyle = style
            carMap.mapStyle = style
        }

        if lastPath !== nav.path {
            lastPath = nav.path
            phoneLine.path = nav.path
            carLine.path = nav.path
            phoneLine.map = nav.path == nil ? nil : phoneMap
            carLine.map = nav.path == nil ? nil : carMap
            if let p = nav.path, !nav.guiding {
                phoneMap.animate(with: GMSCameraUpdate.fit(GMSCoordinateBounds(path: p), withPadding: 90))
            }
        }

        if let s = nav.selected {
            phoneDest.position = s.coordinate
            carDest.position = s.coordinate
            phoneDest.title = s.name
            if phoneDest.map == nil { phoneDest.map = phoneMap }
            if carDest.map == nil { carDest.map = carMap }
        } else {
            phoneDest.map = nil
            carDest.map = nil
        }

        phoneMap.padding = nav.guiding ? UIEdgeInsets(top: 150, left: 0, bottom: 110, right: 0)
                                       : UIEdgeInsets(top: 120, left: 0, bottom: nav.selected == nil ? 20 : 210, right: 0)

        if wasGuiding && !nav.guiding { carMap.camera = phoneMap.camera }
        wasGuiding = nav.guiding

        guard let loc = nav.location else { return }
        if !hadFix {
            hadFix = true
            phoneMap.camera = GMSCameraPosition(target: loc.coordinate, zoom: 15)
        }
        if nav.guiding {
            let bearing = loc.course >= 0 ? loc.course : carMap.camera.bearing
            if follow {
                phoneMap.animate(to: GMSCameraPosition(target: loc.coordinate, zoom: 17.5, bearing: bearing, viewingAngle: 55))
            }
            carMap.animate(to: GMSCameraPosition(target: loc.coordinate, zoom: 16.5, bearing: bearing, viewingAngle: 50))
        }
    }

    func recenter(_ nav: NavModel) {
        follow = true
        if !nav.guiding, let loc = nav.location {
            phoneMap.animate(to: GMSCameraPosition(target: loc.coordinate, zoom: 16))
        }
    }
}

struct PhoneMap: UIViewRepresentable {
    @ObservedObject var nav: NavModel
    @ObservedObject var settings: Settings

    func makeUIView(context: Context) -> GMSMapView { MapController.shared.phoneMap }
    func updateUIView(_ uiView: GMSMapView, context: Context) {
        MapController.shared.update(nav: nav, night: settings.isNight)
    }
}

/// Sits behind the phone map (you never see it on the phone). Pictures of it go to the Tesla.
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
