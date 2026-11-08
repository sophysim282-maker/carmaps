import Foundation
import Network

/// Tiny web server on the iPhone. The Tesla opens it over the hotspot Wi-Fi (no internet needed).
/// "/" = car page, "/stream" = live map pictures, "/state" = directions as JSON.
final class CarServer {
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "carmaps.server")
    private var listener: NWListener?
    private var streams: [ObjectIdentifier: NWConnection] = [:]
    private var busy: Set<ObjectIdentifier> = []
    private var stateJSON = Data("{}".utf8)
    /// Commands from the Tesla screen (called on the main thread).
    var onCommand: ((String, [String: String]) -> Void)?

    private let lock = NSLock()
    private var count = 0
    var hasClients: Bool { lock.lock(); defer { lock.unlock() }; return count > 0 }

    init(port: UInt16) { self.port = NWEndpoint.Port(rawValue: port)! }

    func start() {
        queue.async { self.listen() }
    }

    private func listen() {
        listener?.cancel()
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params, on: port) else {
            queue.asyncAfter(deadline: .now() + 2) { self.listen() }
            return
        }
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.queue.asyncAfter(deadline: .now() + 2) { self?.listen() } }
        }
        l.start(queue: queue)
        listener = l
    }

    func setState(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        queue.async { self.stateJSON = data }
    }

    func broadcast(_ jpeg: Data) {
        queue.async {
            var part = Data("--frame\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpeg.count)\r\n\r\n".utf8)
            part.append(jpeg)
            part.append(Data("\r\n".utf8))
            for (id, conn) in self.streams where !self.busy.contains(id) {
                self.busy.insert(id)
                conn.send(content: part, completion: .contentProcessed { [weak self] error in
                    self?.busy.remove(id)
                    if error != nil { self?.drop(conn) }
                })
            }
        }
    }

    private func accept(_ conn: NWConnection) {
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.drop(conn)
            default: break
            }
        }
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, error in
            guard let self, error == nil, let data, let req = String(data: data, encoding: .utf8) else {
                conn.cancel(); return
            }
            let path = req.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            if path.hasPrefix("/stream") {
                let header = "HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=frame\r\n" +
                    "Cache-Control: no-cache, no-store\r\nPragma: no-cache\r\nConnection: close\r\n\r\n"
                conn.send(content: Data(header.utf8), completion: .contentProcessed { _ in })
                self.streams[ObjectIdentifier(conn)] = conn
                self.updateCount()
            } else if path.hasPrefix("/cmd") {
                var params: [String: String] = [:]
                URLComponents(string: "http://car" + path)?.queryItems?.forEach { params[$0.name] = $0.value ?? "" }
                let action = params["a"] ?? ""
                DispatchQueue.main.async { self.onCommand?(action, params) }
                self.reply(conn, type: "application/json", body: Data("{\"ok\":true}".utf8))
            } else if path.hasPrefix("/state") {
                self.reply(conn, type: "application/json", body: self.stateJSON)
            } else {
                self.reply(conn, type: "text/html; charset=utf-8", body: carPage)
            }
        }
    }

    private func reply(_ conn: NWConnection, type: String, body: Data) {
        var out = Data(("HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\n" +
                        "Cache-Control: no-cache, no-store\r\nConnection: close\r\n\r\n").utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    private func drop(_ conn: NWConnection) {
        let id = ObjectIdentifier(conn)
        if streams.removeValue(forKey: id) != nil {
            busy.remove(id)
            conn.cancel()
            updateCount()
        }
    }

    private func updateCount() {
        lock.lock(); count = streams.count; lock.unlock()
    }
}

/// The page the Tesla browser shows (App/car.html).
private let carPage: Data = {
    if let url = Bundle.main.url(forResource: "car", withExtension: "html"), let d = try? Data(contentsOf: url) { return d }
    return Data("<h1>Car Maps</h1>".utf8)
}()
