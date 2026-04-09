import Foundation
import Observation

@MainActor
@Observable
final class AuthViewModel {
    var currentUser: AppUser?
    var isAuthenticated = false
    var isLoading = false
    var errorMessage: String?

    func checkExistingAuth() {
        isAuthenticated = AuthService.shared.isAuthenticated
    }

    /// Test-mode sign in: registers with a hardcoded email and simulator token.
    /// Replace with real Sign in with Apple once Apple Developer setup is complete.
    func signInWithApple() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await AuthService.shared.register(
                email: "test@statshot.app",
                apnsToken: "simulator-token"
            )
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        AuthService.shared.signOut()
        currentUser = nil
        isAuthenticated = false
    }
}
