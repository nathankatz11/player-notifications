import Foundation

struct AlertItem: Codable, Identifiable {
    let id: String
    let subscriptionId: String
    let userId: String
    let message: String
    let sentAt: Date
    let deliveryMethod: String
    let gameId: String
    let eventDescription: String
}
