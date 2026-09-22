import Foundation

enum AppConfig {
    /// Base URL injected per build configuration from `project.yml`
    /// (`LEDGERLY_BASE_URL`). Falls back to the simulator default.
    static var baseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "LedgerlyBaseURL") as? String,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "http://localhost:3000")!
    }

    /// Token injected per build configuration (`LEDGERLY_API_TOKEN`).
    /// Development builds use the Docker Compose default.
    static var apiToken: String {
        if let token = Bundle.main.object(forInfoDictionaryKey: "LedgerlyAPIToken") as? String, !token.isEmpty {
            return token
        }
        return "local-development-token"
    }
}
