import Foundation

/// Handles authentication via Sign in with Apple.
/// User accounts are stored in the Vercel/Neon backend.
final class AuthService: @unchecked Sendable {
    static let shared = AuthService()

    private(set) var currentUserId: String? {
        get { UserDefaults.standard.string(forKey: "statshot_user_id") }
        set { UserDefaults.standard.set(newValue, forKey: "statshot_user_id") }
    }

    /// The email used for the last successful `/api/register` call. Persisted
    /// so we can re-register (upsert) when APNs hands us a fresh device token
    /// after launch, without needing to re-prompt the user.
    private(set) var currentEmail: String? {
        get { UserDefaults.standard.string(forKey: "statshot_user_email") }
        set { UserDefaults.standard.set(newValue, forKey: "statshot_user_email") }
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
        currentEmail = email
    }

    /// Re-sends the currently stored APNs device token to the backend using the
    /// email we registered with. Called from `AppDelegate` whenever iOS hands
    /// us a fresh device token (first launch after permission, token rotation,
    /// restore from backup, etc.). Safe no-op if the user isn't signed in yet
    /// or no token has been captured.
    @MainActor
    func refreshAPNsToken() async {
        guard let email = currentEmail,
              let token = NotificationService.shared.storedAPNsToken else { return }
        do {
            _ = try await APIService.shared.register(email: email, apnsToken: token)
        } catch {
            print("Failed to refresh APNs token: \(error)")
        }
    }

    func signOut() {
        currentUserId = nil
        currentEmail = nil
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
