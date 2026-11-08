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
            } else if path.hasPrefix("/state") {
                self.reply(conn, type: "application/json", body: self.stateJSON)
            } else {
                self.reply(conn, type: "text/html; charset=utf-8", body: Data(carPage.utf8))
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

/// The page the Tesla browser shows.
private let carPage = """
<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Car Maps</title>
<style>
html,body{margin:0;height:100%;background:#000;color:#fff;font-family:-apple-system,Roboto,sans-serif;overflow:hidden}
#map{position:fixed;inset:0;width:100%;height:100%;object-fit:contain}
#turn{position:fixed;top:16px;left:16px;max-width:46%;background:#0b6b3a;border-radius:18px;padding:18px 22px;
 display:none;box-shadow:0 6px 20px rgba(0,0,0,.5)}
#turn .row{display:flex;gap:16px;align-items:center}
#arrow{font-size:64px;line-height:1}
#dist{font-size:44px;font-weight:800}
#text{font-size:24px;margin-top:6px}
#eta{position:fixed;bottom:16px;left:16px;background:rgba(20,20,22,.9);border-radius:14px;padding:12px 18px;
 font-size:22px;display:none}
#msg{position:fixed;top:50%;width:100%;text-align:center;font-size:24px;color:#aaa;transform:translateY(-50%)}
#btns{position:fixed;right:16px;bottom:16px;display:flex;gap:10px}
button{font:inherit;font-size:18px;border:0;border-radius:12px;padding:12px 16px;background:rgba(60,60,64,.9);color:#fff}
</style></head><body>
<div id="msg">Open Car Maps on your iPhone…</div>
<img id="map" alt="">
<div id="turn"><div class="row"><div id="arrow">⬆️</div><div id="dist"></div></div><div id="text"></div></div>
<div id="eta"></div>
<div id="btns"><button id="voice">🔇 Car voice off</button><button id="fs">Full screen</button></div>
<script>
const $=id=>document.getElementById(id), map=$('map');
const ARROWS={TURN_LEFT:'⬅️',TURN_RIGHT:'➡️',TURN_SLIGHT_LEFT:'↖️',TURN_SLIGHT_RIGHT:'↗️',TURN_SHARP_LEFT:'↙️',
 TURN_SHARP_RIGHT:'↘️',UTURN_LEFT:'↩️',UTURN_RIGHT:'↪️',RAMP_LEFT:'↖️',RAMP_RIGHT:'↗️',FORK_LEFT:'↖️',FORK_RIGHT:'↗️',
 MERGE:'⬆️',ROUNDABOUT_LEFT:'🔄',ROUNDABOUT_RIGHT:'🔄',ROUNDABOUT_CLOCKWISE:'🔄',ROUNDABOUT_COUNTERCLOCKWISE:'🔄',
 FERRY:'⛴️',STRAIGHT:'⬆️',DEPART:'⬆️',NAME_CHANGE:'⬆️',ARRIVE:'🏁'};
function connect(){ map.src='/stream?t='+Date.now(); }
map.onload=()=>{$('msg').style.display='none'};
map.onerror=()=>{$('msg').style.display='block'; setTimeout(connect,1500)};
connect();
let voice=false, lastSpoken=-1;
$('voice').onclick=()=>{ voice=!voice; $('voice').textContent=voice?'🔊 Car voice on':'🔇 Car voice off';
  if(voice&&window.speechSynthesis) speechSynthesis.speak(new SpeechSynthesisUtterance('Voice on')); };
$('fs').onclick=()=>{const d=document.documentElement;(d.requestFullscreen||d.webkitRequestFullscreen||function(){}).call(d)};
async function poll(){
  try{
    const s=await (await fetch('/state?t='+Date.now())).json();
    if(s.navigating){
      $('turn').style.display='block'; $('eta').style.display='block';
      $('arrow').textContent=ARROWS[s.maneuver]||'⬆️'; $('dist').textContent=s.distance;
      $('text').textContent=s.instruction; $('eta').textContent=s.eta+'  ·  '+s.remaining;
    } else { $('turn').style.display='none'; $('eta').style.display='none'; }
    if(lastSpoken<0) lastSpoken=s.spokenId;
    if(voice && s.spokenId!==lastSpoken && window.speechSynthesis){
      speechSynthesis.speak(new SpeechSynthesisUtterance(s.spokenText)); }
    lastSpoken=s.spokenId;
  }catch(e){}
  setTimeout(poll,700);
}
poll();
</script></body></html>
"""
