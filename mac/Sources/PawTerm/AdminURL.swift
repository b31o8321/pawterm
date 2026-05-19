import Foundation

enum AdminURL {
    /// Reads ~/.config/pawterm/config.json and builds the admin URL.
    static func adminURL() -> URL? {
        let configPath = "\(NSHomeDirectory())/.config/pawterm/config.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let port = json["port"] as? Int ?? 8765
        guard let token = json["token"] as? String, !token.isEmpty else { return nil }
        return URL(string: "http://localhost:\(port)/admin?token=\(token)")
    }
}
