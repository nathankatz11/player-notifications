import Foundation

/// Central API client for the Vercel-hosted StatShot backend.
/// All endpoints return JSON and use standard HTTP methods.
final class APIService: Sendable {
    static let shared = APIService()

    private let baseURL = "https://backend-tau-ten-58.vercel.app"

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            // Try with fractional seconds first
            if let date = try? Date(string, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)) {
                return date
            }
            // Fallback without fractional seconds
            if let date = try? Date(string, strategy: .iso8601) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        return d
    }()

    private init() {}

    // MARK: - Registration

    func register(email: String, apnsToken: String) async throws -> String {
        let body: [String: String] = ["email": email, "apnsToken": apnsToken]
        let data = try await post("/api/register", body: body)
        let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return result?["id"] as? String ?? ""
    }

    // MARK: - Teams

    func fetchTeams(league: String) async throws -> [Team] {
        let data = try await get("/api/teams/\(league)")
        let response = try decoder.decode(TeamsResponse.self, from: data)
        return response.teams
    }

    // MARK: - Scores

    func fetchScores(league: String? = nil) async throws -> Data {
        if let league {
            return try await get("/api/scores/\(league)")
        }
        return try await get("/api/scores")
    }

    // MARK: - Search

    func search(query: String, league: String? = nil) async throws -> [SearchResult] {
        var path = "/api/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"
        if let league {
            path += "&league=\(league)"
        }
        let data = try await get(path)
        let response = try decoder.decode(SearchResponse.self, from: data)
        return response.results
    }

    // MARK: - Subscriptions

    func getSubscriptions(userId: String) async throws -> [Subscription] {
        let data = try await get("/api/subscriptions?userId=\(userId)")
        let response = try decoder.decode(SubscriptionsResponse.self, from: data)
        return response.subscriptions
    }

    func createSubscription(_ params: CreateSubscriptionParams) async throws -> Subscription {
        let data = try await post("/api/subscriptions", body: params)
        return try decoder.decode(Subscription.self, from: data)
    }

    func updateSubscription(id: String, active: Bool) async throws {
        _ = try await put("/api/subscriptions/\(id)", body: ["active": active])
    }

    func updateSubscription(id: String, updates: SubscriptionUpdate) async throws {
        _ = try await put("/api/subscriptions/\(id)", body: updates)
    }

    func deleteSubscription(id: String) async throws {
        _ = try await delete("/api/subscriptions/\(id)")
    }

    // MARK: - Trending

    func fetchTrending(league: String) async throws -> [TrendingPlayer] {
        let data = try await get("/api/trending?league=\(league)")
        let response = try decoder.decode(TrendingResponse.self, from: data)
        return response.trending
    }

    // MARK: - Profile

    func getProfile(userId: String) async throws -> ProfileResponse {
        let data = try await get("/api/profile?userId=\(userId)")
        return try decoder.decode(ProfileResponse.self, from: data)
    }

    func updateProfile(userId: String, phone: String? = nil, xHandle: String? = nil) async throws -> ProfileResponse {
        var body: [String: String?] = ["userId": userId]
        if let phone { body["phone"] = phone }
        if let xHandle { body["xHandle"] = xHandle }
        let data = try await patch("/api/profile", body: body)
        return try decoder.decode(ProfileResponse.self, from: data)
    }

    // MARK: - Alerts

    /// Fetches a page of alert history.
    /// - Parameters:
    ///   - userId: The user whose alerts to fetch.
    ///   - limit: Max rows per page (server clamps to 1...100). Defaults to 50.
    ///   - cursor: If non-nil, return rows strictly older than this date.
    /// - Returns: The decoded page of alerts and the next cursor (nil if end of list).
    func getAlertHistory(
        userId: String,
        limit: Int = 50,
        cursor: Date? = nil
    ) async throws -> (alerts: [AlertItem], nextCursor: Date?) {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "userId", value: userId),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let cursor {
            let formatted = cursor.formatted(
                .iso8601.year().month().day().time(includingFractionalSeconds: true)
            )
            components.queryItems?.append(URLQueryItem(name: "cursor", value: formatted))
        }
        let query = components.percentEncodedQuery ?? ""
        let data = try await get("/api/alerts?\(query)")
        let response = try decoder.decode(AlertsResponse.self, from: data)
        return (response.alerts, response.nextCursor)
    }

    // MARK: - HTTP Helpers

    private func get(_ path: String) async throws -> Data {
        try await withRetry(path: path) {
            let url = URL(string: "\(self.baseURL)\(path)")!
            let (data, response) = try await URLSession.shared.data(from: url)
            try self.validateResponse(response, data: data)
            return data
        }
    }

    private func post(_ path: String, body: some Encodable) async throws -> Data {
        let httpBody = try JSONEncoder().encode(body)
        // POST is not retried on HTTP 5xx — the write may have landed server-side
        // and we don't want to duplicate state (e.g. subscriptions).
        return try await withRetry(path: path, retryOn5xx: false) {
            var request = URLRequest(url: URL(string: "\(self.baseURL)\(path)")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = httpBody
            let (data, response) = try await URLSession.shared.data(for: request)
            try self.validateResponse(response, data: data)
            return data
        }
    }

    private func put(_ path: String, body: some Encodable) async throws -> Data {
        let httpBody = try JSONEncoder().encode(body)
        return try await withRetry(path: path) {
            var request = URLRequest(url: URL(string: "\(self.baseURL)\(path)")!)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = httpBody
            let (data, response) = try await URLSession.shared.data(for: request)
            try self.validateResponse(response, data: data)
            return data
        }
    }

    private func patch(_ path: String, body: some Encodable) async throws -> Data {
        let httpBody = try JSONEncoder().encode(body)
        return try await withRetry(path: path) {
            var request = URLRequest(url: URL(string: "\(self.baseURL)\(path)")!)
            request.httpMethod = "PATCH"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = httpBody
            let (data, response) = try await URLSession.shared.data(for: request)
            try self.validateResponse(response, data: data)
            return data
        }
    }

    private func delete(_ path: String) async throws -> Data {
        try await withRetry(path: path) {
            var request = URLRequest(url: URL(string: "\(self.baseURL)\(path)")!)
            request.httpMethod = "DELETE"
            let (data, response) = try await URLSession.shared.data(for: request)
            try self.validateResponse(response, data: data)
            return data
        }
    }

    // MARK: - Retry

    /// Retries transient failures up to `attempts` times with exponential backoff
    /// (200ms then 800ms). Set `retryOn5xx` to false for non-idempotent verbs (POST)
    /// where a 5xx might mean the write landed and a retry would duplicate state.
    ///
    /// TODO: Parse `Retry-After` header on HTTP 429 instead of using the fixed
    /// 800ms backoff. Would require surfacing the `HTTPURLResponse` out of the
    /// operation closure.
    private func withRetry<T>(
        path: String,
        attempts: Int = 3,
        retryOn5xx: Bool = true,
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0..<attempts {
            do {
                return try await operation()
            } catch let error where self.shouldRetry(error, retryOn5xx: retryOn5xx) && attempt < attempts - 1 {
                lastError = error
                print("[APIService] Retrying \(path) after \(error)")
                let backoffMs = attempt == 0 ? 200 : 800
                try? await Task.sleep(for: .milliseconds(backoffMs))
            } catch {
                throw error
            }
        }
        throw lastError ?? APIError.invalidResponse
    }

    private func shouldRetry(_ error: Error, retryOn5xx: Bool) -> Bool {
        if let api = error as? APIError, case .httpError(let code) = api {
            if code == 429 { return true }
            if retryOn5xx, code >= 500, code < 600 { return true }
            return false
        }
        if let url = error as? URLError {
            return [.timedOut, .cannotConnectToHost, .networkConnectionLost,
                    .dnsLookupFailed, .notConnectedToInternet].contains(url.code)
        }
        return false
    }

    private func validateResponse(_ response: URLResponse, data: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            // Try to parse the server's error message
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["error"] as? String {
                throw APIError.serverMessage(message)
            }
            throw APIError.httpError(statusCode: http.statusCode)
        }
    }
}

// MARK: - Request/Response Types

struct CreateSubscriptionParams: Encodable {
    let userId: String
    let type: String
    let league: String
    let entityId: String
    let entityName: String
    let trigger: String
    let deliveryMethod: String
}

struct SubscriptionUpdate: Encodable {
    var trigger: String?
    var deliveryMethod: String?
    var active: Bool?
}

struct SearchResponse: Decodable {
    let results: [SearchResult]
}

struct SubscriptionsResponse: Decodable {
    let subscriptions: [Subscription]
}

struct AlertsResponse: Decodable {
    let alerts: [AlertItem]
    let nextCursor: Date?
}

struct Team: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let abbreviation: String
    let logoUrl: String?
}

struct TeamsResponse: Decodable, Sendable {
    let teams: [Team]
}

struct TrendingPlayer: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let league: String
    let plays: Int
    let team: String
}

struct TrendingResponse: Decodable, Sendable {
    let trending: [TrendingPlayer]
}

struct ProfileResponse: Decodable, Sendable {
    let id: String
    let email: String?
    let phone: String?
    let xHandle: String?
    let plan: String?
}

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid server response"
        case .httpError(let code):
            "Server error (HTTP \(code))"
        case .serverMessage(let message):
            message
        }
    }
}
