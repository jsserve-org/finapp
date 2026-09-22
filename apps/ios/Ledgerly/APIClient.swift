import Foundation

enum APIError: Error, Equatable {
    case invalidResponse
    case http(Int)
    case offline
}

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

    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(baseURL: URL = AppConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    private func token() -> String {
        KeychainStore().token() ?? AppConfig.apiToken
    }

    private func makeRequest(path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token())", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        request.timeoutInterval = 15
        return request
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
