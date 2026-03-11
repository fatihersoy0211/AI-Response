import Foundation

enum AppConfig {
    /// On Simulator 127.0.0.1 reaches the Mac host.
    /// On a real iPhone, set BACKEND_BASE_URL in the scheme's environment variables,
    /// e.g.  http://192.168.x.x:8080  (your Mac's Wi-Fi IP while on the same network).
    static let baseURL: URL = {
        if let raw = ProcessInfo.processInfo.environment["BACKEND_BASE_URL"],
           let url = URL(string: raw) {
            return url
        }
        #if targetEnvironment(simulator)
        return URL(string: "http://127.0.0.1:8080")!
        #else
        // ⚠️  Change this to your Mac's LAN IP, or set BACKEND_BASE_URL in the scheme.
        return URL(string: "http://127.0.0.1:8080")!
        #endif
    }()
}
