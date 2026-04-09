import Foundation

/// Handles authentication via Sign in with Apple.
/// User accounts are stored in the Vercel/Neon backend.
final class AuthService: @unchecked Sendable {
    static let shared = AuthService()

    private(set) var currentUserId: String? {
        get { UserDefaults.standard.string(forKey: "statshot_user_id") }
        set { UserDefaults.standard.set(newValue, forKey: "statshot_user_id") }
    }

    var isAuthenticated: Bool { currentUserId != nil }

    private init() {}

    func signInWithApple() async throws -> String {
        // TODO: Implement Sign in with Apple flow:
        // 1. Create ASAuthorizationAppleIDProvider request
        // 2. Present ASAuthorizationController
        // 3. Get Apple ID credential (email, identity token)
        // 4. Call POST /api/register with email + APNs token
        // 5. Store returned userId locally
        throw AuthError.notImplemented
    }

    func register(email: String, apnsToken: String) async throws {
        let userId = try await APIService.shared.register(email: email, apnsToken: apnsToken)
        currentUserId = userId
    }

    func signOut() {
        currentUserId = nil
    }
}

enum AuthError: LocalizedError {
    case notImplemented
    case signInFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            "Authentication not yet configured"
        case .signInFailed(let error):
            "Sign in failed: \(error.localizedDescription)"
        }
    }
}
