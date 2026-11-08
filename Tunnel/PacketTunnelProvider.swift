import NetworkExtension

/// A "VPN" that does not touch your internet. It only gives the iPhone the extra address 240.3.3.3,
/// so the Tesla browser (on the iPhone hotspot) can open http://240.3.3.3:8080.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "240.3.3.4")
        let ipv4 = NEIPv4Settings(addresses: ["240.3.3.3"], subnetMasks: ["255.255.255.255"])
        ipv4.includedRoutes = []          // all normal internet stays outside the VPN
        settings.ipv4Settings = ipv4
        settings.mtu = 1500
        setTunnelNetworkSettings(settings) { error in
            completionHandler(error)
            if error == nil { self.drain() }
        }
    }

    /// Nothing should come in, but read and drop anything that does.
    private func drain() {
        packetFlow.readPackets { [weak self] _, _ in self?.drain() }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
