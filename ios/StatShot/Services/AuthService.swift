import Foundation

/// Handles Firebase Auth operations.
/// TODO: Import FirebaseAuth once Firebase SDK is added via SPM.
final class AuthService {
    static let shared = AuthService()

    private init() {}

    var currentUserId: String? {
        // TODO: Return Firebase Auth current user UID
        return nil
    }

    var isAuthenticated: Bool {
        currentUserId != nil
    }

    func signInWithApple() async throws -> String {
        // TODO: Implement Sign in with Apple flow:
        // 1. Create ASAuthorizationAppleIDProvider request
        // 2. Present ASAuthorizationController
        // 3. Get Apple ID credential from delegate
        // 4. Create OAuthProvider credential for Firebase
        // 5. Sign in with Firebase Auth
        // 6. Return user ID
        throw AuthError.notImplemented
    }

    func signOut() throws {
        // TODO: Firebase Auth sign out
    }
}

enum AuthError: LocalizedError {
    case notImplemented
    case signInFailed(underlying: Error)
    case signOutFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            "Authentication not yet configured"
        case .signInFailed(let error):
            "Sign in failed: \(error.localizedDescription)"
        case .signOutFailed(let error):
            "Sign out failed: \(error.localizedDescription)"
        }
    }
}
