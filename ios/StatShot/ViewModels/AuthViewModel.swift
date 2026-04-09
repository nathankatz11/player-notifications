import Foundation
import Observation

@Observable
final class AuthViewModel {
    var currentUser: AppUser?
    var isAuthenticated = false
    var isLoading = false
    var errorMessage: String?

    func signInWithApple() async {
        isLoading = true
        defer { isLoading = false }

        // TODO: Firebase Auth — Sign in with Apple
        // 1. Get Apple ID credential via ASAuthorizationController
        // 2. Create Firebase credential from Apple token
        // 3. Sign in with Firebase Auth
        // 4. Fetch/create user doc in Firestore
        // 5. Register FCM token

        isAuthenticated = true
    }

    func signOut() {
        // TODO: Firebase Auth sign out
        currentUser = nil
        isAuthenticated = false
    }
}
