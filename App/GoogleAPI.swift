import Foundation

/// Calls Google Maps Platform web APIs with the user's key.
final class GoogleAPI {
    let key: String
    init(key: String) { self.key = key }

    /// POST when there is a body, GET otherwise. Calls back on the main thread with JSON or an error text.
    func call(_ url: String, body: [String: Any]? = nil, fields: String? = nil,
              done: @escaping ([String: Any]?, String?) -> Void) {
        guard let u = URL(string: url) else { done(nil, "Bad URL"); return }
        var req = URLRequest(url: u)
        req.httpMethod = body == nil ? "GET" : "POST"
        req.timeoutInterval = 15
        req.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        req.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        if let fields { req.setValue(fields, forHTTPHeaderField: "X-Goog-FieldMask") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async {
                if let err {
                    done(nil, "No internet: \(err.localizedDescription)")
                } else if code != 200 {
                    let msg = (json?["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(code)"
                    done(nil, "Google error: \(msg)")
                } else {
                    done(json ?? [:], nil)
                }
            }
        }.resume()
    }

    func photoURL(_ name: String, width: Int = 800) -> URL? {
        URL(string: "https://places.googleapis.com/v1/\(name)/media?maxWidthPx=\(width)&key=\(key)")
    }
}
