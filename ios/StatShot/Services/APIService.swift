import Foundation

/// Central API client for the Vercel-hosted StatShot backend.
/// All endpoints return JSON and use standard HTTP methods.
final class APIService: Sendable {
    static let shared = APIService()

    private let baseURL = "https://backend-tau-ten-58.vercel.app"

    private nonisolated(unsafe) let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = formatter.date(from: string) {
                return date
            }
            // Fallback without fractional seconds
            let basic = ISO8601DateFormatter()
            basic.formatOptions = [.withInternetDateTime]
            if let date = basic.date(from: string) {
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

    func getAlertHistory(userId: String) async throws -> [AlertItem] {
        let data = try await get("/api/alerts?userId=\(userId)")
        let response = try decoder.decode(AlertsResponse.self, from: data)
        return response.alerts
    }

    // MARK: - HTTP Helpers

    private func get(_ path: String) async throws -> Data {
        let url = URL(string: "\(baseURL)\(path)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response, data: data)
        return data
    }

    private func post(_ path: String, body: some Encodable) async throws -> Data {
        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return data
    }

    private func put(_ path: String, body: some Encodable) async throws -> Data {
        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return data
    }

    private func patch(_ path: String, body: some Encodable) async throws -> Data {
        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return data
    }

    private func delete(_ path: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = "DELETE"
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return data
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
