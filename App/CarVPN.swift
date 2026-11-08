import Foundation
import NetworkExtension

/// Turns the 240.3.3.3 address on and off (iPhone Settings shows it as a VPN called "Car Maps").
final class CarVPN: ObservableObject {
    static let address = "240.3.3.3"
    @Published var status: NEVPNStatus = .invalid
    @Published var error: String?
    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?

    var isOn: Bool { status == .connected }
    var statusText: String {
        switch status {
        case .connected: return "On"
        case .connecting, .reasserting: return "Turning on…"
        case .disconnecting: return "Turning off…"
        default: return "Off"
        }
    }

    init() {
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { [weak self] n in
            if let c = n.object as? NEVPNConnection { self?.status = c.status }
        }
        NETunnelProviderManager.loadAllFromPreferences { [weak self] list, _ in
            DispatchQueue.main.async {
                self?.manager = list?.first
                self?.status = list?.first?.connection.status ?? .invalid
            }
        }
    }

    func turnOn() {
        error = nil
        NETunnelProviderManager.loadAllFromPreferences { [weak self] list, err in
            guard let self else { return }
            let m = list?.first ?? NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = (Bundle.main.bundleIdentifier ?? "") + ".tunnel"
            proto.serverAddress = Self.address
            m.protocolConfiguration = proto
            m.localizedDescription = "Car Maps (Tesla link)"
            m.isEnabled = true
            m.saveToPreferences { err in
                if let err { DispatchQueue.main.async { self.error = err.localizedDescription }; return }
                m.loadFromPreferences { _ in
                    do {
                        try m.connection.startVPNTunnel()
                    } catch {
                        DispatchQueue.main.async { self.error = error.localizedDescription }
                    }
                    DispatchQueue.main.async {
                        self.manager = m
                        self.status = m.connection.status
                    }
                }
            }
        }
    }

    func turnOff() {
        manager?.connection.stopVPNTunnel()
    }
}
