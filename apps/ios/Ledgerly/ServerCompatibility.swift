import Foundation

enum LedgerlyCompatibility: Equatable {
    static let syncProtocolVersion = 2
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    case compatible
    case appOutdated(latest: String)
    case appUnsupported(minimum: String)
    case serverOutdated
    case protocolMismatch(server: Int)

    static func evaluate(_ config: ServerConfig) -> LedgerlyCompatibility {
        guard let protocolVersion = config.syncProtocolVersion,
              config.serverVersion != nil else { return .serverOutdated }
        guard protocolVersion == syncProtocolVersion else { return .protocolMismatch(server: protocolVersion) }
        if let minimum = config.minimumAppVersion, compare(appVersion, minimum) == .orderedAscending {
            return .appUnsupported(minimum: minimum)
        }
        if let latest = config.latestAppVersion, compare(appVersion, latest) == .orderedAscending {
            return .appOutdated(latest: latest)
        }
        return .compatible
    }

    var message: String {
        switch self {
        case .compatible: "App and server are compatible"
        case .appOutdated(let latest): "App update available: \(latest)"
        case .appUnsupported(let minimum): "Update the app to \(minimum) or newer"
        case .serverOutdated: "Server update required"
        case .protocolMismatch(let server): "Sync protocol mismatch (server \(server), app \(Self.syncProtocolVersion))"
        }
    }

    var canSync: Bool {
        switch self {
        case .compatible, .appOutdated: true
        default: false
        }
    }

    private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: .numeric)
    }
}
