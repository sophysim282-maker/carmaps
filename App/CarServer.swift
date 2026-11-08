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
:root{--card:#fff;--text:#202124;--muted:#5f6368;--eta:#188038}
.night{--card:#202124;--text:#e8eaed;--muted:#9aa0a6;--eta:#81c995}
html,body{margin:0;height:100%;background:#000;font-family:Roboto,-apple-system,"Segoe UI",sans-serif;overflow:hidden}
#map{position:fixed;inset:0;width:100%;height:100%;object-fit:cover;visibility:hidden}
#turn{position:fixed;top:20px;left:20px;width:min(520px,44vw);background:#0d7a45;color:#fff;border-radius:20px;
 padding:20px 24px;display:none;gap:20px;align-items:center;box-shadow:0 6px 24px rgba(0,0,0,.45)}
#turn svg{width:84px;height:84px;flex:none}
#dist{font-size:46px;font-weight:700;line-height:1.05}
#text{font-size:26px;font-weight:500;margin-top:4px;line-height:1.2}
#eta{position:fixed;bottom:20px;left:20px;background:var(--card);color:var(--text);border-radius:20px;
 padding:14px 26px;display:none;box-shadow:0 6px 24px rgba(0,0,0,.4)}
#etaTime{font-size:36px;font-weight:700;color:var(--eta)}
#etaSub{font-size:20px;color:var(--muted)}
#msg{position:fixed;top:50%;width:100%;text-align:center;font-size:26px;color:#aaa;transform:translateY(-50%)}
#btns{position:fixed;right:20px;bottom:20px;display:flex;gap:12px}
button{font:inherit;font-size:19px;border:0;border-radius:14px;padding:14px 18px;background:var(--card);color:var(--text);
 box-shadow:0 4px 14px rgba(0,0,0,.35)}
</style></head><body>
<div id="msg">Open Car Maps on your iPhone…</div>
<img id="map" alt="">
<div id="turn"><svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round"
 stroke-linejoin="round"><g id="icon"></g></svg><div><div id="dist"></div><div id="text"></div></div></div>
<div id="eta"><div id="etaTime"></div><div id="etaSub"></div></div>
<div id="btns"><button id="voice">🔇 Voice off</button><button id="fs">⛶ Full screen</button></div>
<script>
const $=id=>document.getElementById(id), map=$('map');
const L='<path d="M16 21v-8a4 4 0 0 0-4-4H5"/><path d="M9 5L5 9l4 4"/>';
const R='<g transform="translate(24 0) scale(-1 1)">'+L+'</g>';
const SL='<path d="M15 21v-7L7 6"/><path d="M7 12V6h6"/>';
const SR='<g transform="translate(24 0) scale(-1 1)">'+SL+'</g>';
const UT='<path d="M15 21V9a4 4 0 0 0-8 0v6"/><path d="M4 12l3 3 3-3"/>';
const ST='<path d="M12 21V4"/><path d="M6 10l6-6 6 6"/>';
const RB='<circle cx="12" cy="9" r="4"/><path d="M12 21v-8"/><path d="M16 9h4"/><path d="M18 7l2 2-2 2"/>';
const AR='<path d="M6 21V4"/><path d="M6 4h11l-2.5 4L17 12H6"/>';
const ICON={TURN_LEFT:L,TURN_SHARP_LEFT:L,TURN_RIGHT:R,TURN_SHARP_RIGHT:R,TURN_SLIGHT_LEFT:SL,RAMP_LEFT:SL,FORK_LEFT:SL,
 TURN_SLIGHT_RIGHT:SR,RAMP_RIGHT:SR,FORK_RIGHT:SR,UTURN_LEFT:UT,UTURN_RIGHT:UT,ROUNDABOUT_LEFT:RB,ROUNDABOUT_RIGHT:RB,
 ROUNDABOUT_CLOCKWISE:RB,ROUNDABOUT_COUNTERCLOCKWISE:RB,ARRIVE:AR};
function connect(){ map.src='/stream?t='+Date.now(); }
map.onload=()=>{$('msg').style.display='none';map.style.visibility='visible'};
map.onerror=()=>{$('msg').style.display='block'; setTimeout(connect,1500)};
connect();
let voice=false,lastSpoken=-1,lang='en';
function speak(t){ if(!window.speechSynthesis) return; const u=new SpeechSynthesisUtterance(t); u.lang=lang; speechSynthesis.speak(u); }
$('voice').onclick=()=>{voice=!voice;$('voice').textContent=voice?'🔊 Voice on':'🔇 Voice off'; if(voice) speak('OK');};
$('fs').onclick=()=>{const d=document.documentElement;(d.requestFullscreen||d.webkitRequestFullscreen||function(){}).call(d)};
async function poll(){
  try{
    const s=await (await fetch('/state?t='+Date.now())).json();
    document.body.classList.toggle('night',!!s.night);
    lang=s.lang||'en';
    const on=!!s.navigating;
    $('turn').style.display=on?'flex':'none'; $('eta').style.display=on?'block':'none';
    if(on){
      $('icon').innerHTML=ICON[s.maneuver]||ST; $('dist').textContent=s.distance; $('text').textContent=s.instruction;
      $('etaTime').textContent=s.eta; $('etaSub').textContent=s.remaining+' · '+s.arrival;
    }
    if(lastSpoken<0) lastSpoken=s.spokenId;
    if(voice && s.spokenId!==lastSpoken) speak(s.spokenText);
    lastSpoken=s.spokenId;
  }catch(e){}
  setTimeout(poll,700);
}
poll();
</script></body></html>
"""
