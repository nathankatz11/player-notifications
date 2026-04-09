import Foundation

/// Handles Stripe payment operations for the premium subscription.
/// TODO: Import StripePaymentSheet once Stripe iOS SDK is added via SPM.
final class StripeService {
    static let shared = StripeService()

    private init() {}

    func presentPaymentSheet() async throws -> Bool {
        // TODO: Implement Stripe payment flow:
        // 1. Call backend to create PaymentIntent
        // 2. Configure PaymentSheet with client secret
        // 3. Present PaymentSheet
        // 4. Handle result
        // 5. Update user plan in Firestore on success
        throw PaymentError.notImplemented
    }

    func restorePurchases() async throws {
        // TODO: Check Stripe for active subscription linked to this user
    }
}

enum PaymentError: LocalizedError {
    case notImplemented
    case paymentFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            "Payments not yet configured"
        case .paymentFailed(let message):
            "Payment failed: \(message)"
        }
    }
}
