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

    /// Runs the real Sign in with Apple flow. On success, persists the backend
    /// userId + email in Keychain (via AuthService) and then forwards any
    /// cached APNs token so pushes start flowing. On failure, surfaces a
    /// user-visible error message and leaves `isAuthenticated` alone so the
    /// UI can re-present the sign-in button.
    func signInWithApple() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Kick off the native SIWA sheet (modal). Blocks until user either
            // completes or cancels; cancellation surfaces as
            // ASAuthorizationError.canceled, which we treat as a no-op
            // (no error banner, stays on sign-in screen).
            _ = try await AuthService.shared.signInWithApple()

            // Wait briefly for the APNs token (if we don't already have one),
            // then upsert the device/user via /api/register so the user row
            // has the latest token. On simulator this times out and the
            // register call is skipped.
            if let email = AuthService.shared.currentEmail {
                let apnsToken = await NotificationService.shared.awaitDeviceToken(
                    timeout: .seconds(3)
                )
                if let apnsToken {
                    _ = try? await APIService.shared.register(
                        email: email,
                        apnsToken: apnsToken
                    )
                }
            }

            isAuthenticated = true
            await loadProfile()
        } catch {
            if isUserCancellation(error) {
                // User tapped Cancel on the SIWA sheet — stay silent.
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    /// Detects "user canceled" from an underlying `ASAuthorizationError`
    /// without forcing a direct import of `AuthenticationServices` into this
    /// file. `ASAuthorizationError.canceled.rawValue == 1001`.
    private func isUserCancellation(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == "com.apple.AuthenticationServices.AuthorizationError"
            && ns.code == 1001 {
            return true
        }
        // Our wrapped form.
        if case AuthError.signInFailed(let underlying) = error {
            let underNS = underlying as NSError
            return underNS.domain == "com.apple.AuthenticationServices.AuthorizationError"
                && underNS.code == 1001
        }
        return false
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

