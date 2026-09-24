import Foundation

enum AppConfig {
    /// Base URL injected per build configuration from `project.yml`
    /// (`LEDGERLY_BASE_URL`). Falls back to the simulator default.
    static var baseURL: URL {
        if let raw = UserDefaults.standard.string(forKey: "ledgerly.apiURL"),
           let url = URL(string: raw), url.host != "localhost" {
            return url
        }
        if let raw = Bundle.main.object(forInfoDictionaryKey: "LedgerlyBaseURL") as? String,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "http://10.99.1.6:3000")!
    }

    static var convexURL: URL {
        if let raw = UserDefaults.standard.string(forKey: "ledgerly.convexURL"),
           let url = URL(string: raw), url.host != "localhost" {
            return url
        }
        return URL(string: "http://10.99.1.6:3210")!
    }

}
