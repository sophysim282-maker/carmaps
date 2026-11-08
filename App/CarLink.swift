import UIKit
import Network
import ReplayKit
import CoreImage

/// Sends the app's own map (pictures) + the directions (text) to the Tesla browser over local Wi-Fi.
final class CarLink: ObservableObject {
    @Published var carConnected = false
    let server = CarServer(port: 8080)
    private var timer: Timer?
    private var blackFrames = 0
    private var useInAppCapture = false
    private let encodeQueue = DispatchQueue(label: "carmaps.encode")
    private let ciContext = CIContext()

    func start(state: @escaping () -> [String: Any]) {
        server.start()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 8.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let connected = self.server.hasClients
            if connected != self.carConnected { self.carConnected = connected }
            self.server.setState(state())
            if connected && !self.useInAppCapture { self.snapshot() }
        }
    }

    /// Normal mode: draw the wide car map into a picture.
    private func snapshot() {
        let view = MapController.shared.carMap
        guard view.window != nil, view.bounds.width > 0,
              UIApplication.shared.applicationState == .active else { return }
        let longest = max(view.bounds.width, view.bounds.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(UIScreen.main.scale, max(1, 1280 / longest))
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
        // Some iPhones return a black picture for the map; then switch to in-app capture.
        if Self.isBlack(image) {
            blackFrames += 1
            if blackFrames >= 5 { startInAppCapture() }
            return
        }
        blackFrames = 0
        encodeQueue.async { [server] in
            if let jpeg = image.jpegData(compressionQuality: 0.6) { server.broadcast(jpeg) }
        }
    }

    /// Backup mode: Apple's in-app capture. Captures ONLY this app, never other apps.
    private func startInAppCapture() {
        useInAppCapture = true
        let recorder = RPScreenRecorder.shared()
        recorder.isMicrophoneEnabled = false
        var last: CFTimeInterval = 0
        recorder.startCapture(handler: { [weak self] buffer, type, _ in
            guard let self, type == .video, self.server.hasClients else { return }
            let now = CACurrentMediaTime()
            guard now - last >= 1.0 / 10.0, let pb = CMSampleBufferGetImageBuffer(buffer) else { return }
            last = now
            var img = CIImage(cvPixelBuffer: pb)
            let longest = max(img.extent.width, img.extent.height)
            if longest > 1280 { img = img.transformed(by: CGAffineTransform(scaleX: 1280 / longest, y: 1280 / longest)) }
            let opts = [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.6]
            if let jpeg = self.ciContext.jpegRepresentation(of: img, colorSpace: CGColorSpaceCreateDeviceRGB(), options: opts) {
                self.server.broadcast(jpeg)
            }
        }, completionHandler: { [weak self] error in
            if error != nil { self?.useInAppCapture = false; self?.blackFrames = 0 }
        })
    }

    private static func isBlack(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return true }
        var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
        guard let ctx = CGContext(data: &pixels, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 8, height: 8))
        return pixels.max() ?? 0 < 12
    }
}

/// IPv4 addresses on Wi-Fi / hotspot, as car-browser URLs.
func carAddresses() -> [String] {
    var result: [String] = []
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return ["http://172.20.10.1:8080"] }
    defer { freeifaddrs(ifaddr) }
    for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
        let ifa = ptr.pointee
        guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
        let name = String(cString: ifa.ifa_name)
        guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
            let url = "http://\(String(cString: host)):8080"
            if !result.contains(url) { result.append(url) }
        }
    }
    if !result.contains("http://172.20.10.1:8080") { result.insert("http://172.20.10.1:8080", at: 0) }
    result.removeAll { $0.contains(CarVPN.address) }
    result.insert("http://\(CarVPN.address):8080", at: 0)
    return result
}
