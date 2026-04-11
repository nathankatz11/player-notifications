import Foundation

enum UserPlan: String, Codable {
    case free
    case premium
}

struct AppUser: Codable {
    let id: String
    let email: String
    let phone: String?
    let xHandle: String?
    let fcmToken: String?
    let plan: UserPlan
    let createdAt: Date?
}
