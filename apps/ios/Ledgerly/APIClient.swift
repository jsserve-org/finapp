import Foundation

enum APIError: Error, Equatable {
    case invalidResponse
    case http(Int)
    case offline
}

struct AuthResponse: Codable {
    struct User: Codable { let username: String }
    struct Context: Codable { let apiUrl, convexUrl, syncSessionId, expiresAt: String }
    let token: String
    let user: User
    let context: Context
}
struct ServerConfig: Codable { let registrationEnabled: Bool; let convexUrl: String }

struct ConnectionStatus: Codable, Equatable {
    let connectionId: String
    let state: String
    let lastSuccessAt: String?
    let lastError: String?
    let nextCheckAt: String
}

/// Actor wrapping all calls to the Docker Compose API. Endpoint shapes match
/// `apps/api/src/app.ts` and `apps/api/src/routes/sync.ts`.
actor APIClient {
    static let shared = APIClient()

    private let configuredBaseURL: URL?
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(baseURL: URL = AppConfig.baseURL, session: URLSession = .shared) {
        self.configuredBaseURL = baseURL == AppConfig.baseURL ? nil : baseURL
        self.session = session
    }

    private func token() -> String {
        KeychainStore().token() ?? ""
    }

    private func makeRequest(path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: (configuredBaseURL ?? AppConfig.baseURL).appending(path: path))
        request.httpMethod = method
        let bearer = token()
        if !bearer.isEmpty { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        request.timeoutInterval = 15
        return request
    }

    func authenticate(username: String, password: String, convexURL: URL, register: Bool = false) async throws -> AuthResponse? {
        struct Body: Encodable { let username, password, convexUrl: String }
        let body = try JSONEncoder().encode(Body(username: username, password: password, convexUrl: convexURL.absoluteString))
        let request = makeRequest(path: register ? "/v1/auth/register" : "/v1/auth/login", method: "POST", body: body)
        let data = try await send(request)
        return register ? nil : try decoder.decode(AuthResponse.self, from: data)
    }

    func serverConfig() async throws -> ServerConfig {
        try decoder.decode(ServerConfig.self, from: await send(makeRequest(path: "/v1/config")))
    }

    func logout() async throws {
        _ = try await send(makeRequest(path: "/v1/auth/logout", method: "POST"))
    }

    private func send(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
            return data
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.offline
        }
    }

    // MARK: - Sync

    private struct SyncRequestBody: Encodable {
        let cursor: String?
        let operations: [SyncOperation]
    }

    func sync(cursor: String?, operations: [SyncOperation] = []) async throws -> SyncResponse {
        let body = try JSONEncoder().encode(SyncRequestBody(cursor: cursor, operations: operations))
        let request = makeRequest(path: "/v1/sync", method: "POST", body: body)
        return try decoder.decode(SyncResponse.self, from: await send(request))
    }

    // MARK: - Health & connections

    func healthReady() async throws {
        _ = try await send(makeRequest(path: "/health/ready"))
    }

    func connectionStatuses() async throws -> [ConnectionStatus] {
        try decoder.decode([ConnectionStatus].self, from: await send(makeRequest(path: "/v1/automations/status")))
    }

    func runDemoAutomation() async throws {
        _ = try await send(makeRequest(path: "/v1/automations/demo/run", method: "POST"))
    }
}
