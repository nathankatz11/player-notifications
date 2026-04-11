import Foundation
import Observation

@MainActor
@Observable
final class AuthViewModel {
    var currentUser: AppUser?
    var isAuthenticated = false
    var isLoading = false
    var errorMessage: String?

    // Editable contact fields (loaded from profile)
    var phone: String = ""
    var xHandle: String = ""

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
            await loadProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadProfile() async {
        guard let userId = AuthService.shared.currentUserId else { return }
        do {
            let profile = try await APIService.shared.getProfile(userId: userId)
            phone = profile.phone ?? ""
            xHandle = profile.xHandle ?? ""
        } catch {
            // Non-critical — silently ignore
        }
    }

    func saveProfile() async {
        guard let userId = AuthService.shared.currentUserId else { return }
        do {
            let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
            let trimmedHandle = xHandle.trimmingCharacters(in: .whitespaces)
            _ = try await APIService.shared.updateProfile(
                userId: userId,
                phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
                xHandle: trimmedHandle.isEmpty ? nil : trimmedHandle
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        AuthService.shared.signOut()
        currentUser = nil
        isAuthenticated = false
        phone = ""
        xHandle = ""
    }
}
