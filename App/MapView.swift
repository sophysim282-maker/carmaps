import SwiftUI
import GoogleMaps

/// One shared Google map view, so the car streamer can take pictures of it.
final class MapHolder {
    static let shared = MapHolder()
    lazy var mapView: GMSMapView = {
        let m = GMSMapView(frame: .zero, camera: GMSCameraPosition(latitude: 11.5564, longitude: 104.9282, zoom: 12))
        m.isMyLocationEnabled = true
        m.settings.myLocationButton = false
        m.settings.compassButton = true
        m.isTrafficEnabled = true
        return m
    }()
    let routeLine = GMSPolyline()
    var follow = true
}

struct MapView: UIViewRepresentable {
    @ObservedObject var nav: NavModel

    func makeUIView(context: Context) -> GMSMapView {
        let h = MapHolder.shared
        h.routeLine.strokeWidth = 7
        h.routeLine.strokeColor = UIColor.systemBlue
        h.mapView.delegate = context.coordinator
        return h.mapView
    }

    func updateUIView(_ map: GMSMapView, context: Context) {
        let h = MapHolder.shared
        if h.routeLine.path !== nav.path {
            h.routeLine.path = nav.path
            h.routeLine.map = nav.path == nil ? nil : map
        }
        guard let loc = nav.location else { return }
        if context.coordinator.firstFix {
            context.coordinator.firstFix = false
            map.camera = GMSCameraPosition(target: loc.coordinate, zoom: 15)
        } else if h.follow && nav.navigating {
            let bearing = loc.course >= 0 ? loc.course : map.camera.bearing
            map.animate(to: GMSCameraPosition(target: loc.coordinate, zoom: 17, bearing: bearing, viewingAngle: 45))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var firstFix = true
        // When the user drags the map, stop following until they tap "Re-center".
        func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
            if gesture { MapHolder.shared.follow = false }
        }
    }
}
