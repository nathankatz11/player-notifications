import AuthenticationServices
import Foundation
import UIKit

/// Handles authentication via Sign in with Apple.
/// User accounts are stored in the Vercel/Neon backend, keyed by Apple's
/// stable `sub` claim. Credentials (userId + email + appleUserId) are
/// persisted in the Keychain, not `UserDefaults`, because they're auth
/// material. A one-time migration copies any legacy `UserDefaults` entries
/// over on first launch after update.
final class AuthService: @unchecked Sendable {
    static let shared = AuthService()

    // MARK: - Storage (Keychain-backed, with UserDefaults migration)

    /// Stable backend user UUID (returned by `/api/auth/apple`).
    private(set) var currentUserId: String? {
        get { Keychain.load(key: Keychain.Keys.userId) }
        set {
            if let v = newValue {
                Keychain.save(key: Keychain.Keys.userId, value: v)
                // Mirror into UserDefaults during the transition so
                // `refreshAPNsToken` and any other legacy readers keep
                // working. Safe to remove once all testers have launched
                // the updated app at least once.
                UserDefaults.standard.set(v, forKey: "statshot_user_id")
            } else {
                Keychain.delete(key: Keychain.Keys.userId)
                UserDefaults.standard.removeObject(forKey: "statshot_user_id")
            }
        }
    }

    /// Email used at registration. May be `nil` for users who signed in with
    /// SIWA after the first time (Apple only provides the email on the very
    /// first sign-in per Apple-ID / app combination).
    private(set) var currentEmail: String? {
        get { Keychain.load(key: Keychain.Keys.userEmail) }
        set {
            if let v = newValue {
                Keychain.save(key: Keychain.Keys.userEmail, value: v)
                UserDefaults.standard.set(v, forKey: "statshot_user_email")
            } else {
                Keychain.delete(key: Keychain.Keys.userEmail)
                UserDefaults.standard.removeObject(forKey: "statshot_user_email")
            }
        }
    }

    /// Apple's stable user id (`sub` from the SIWA JWT). Used for future
    /// re-auth flows and as a local "is this still the same Apple ID" check.
    private(set) var currentAppleUserId: String? {
        get { Keychain.load(key: Keychain.Keys.appleUserId) }
        set {
            if let v = newValue {
                Keychain.save(key: Keychain.Keys.appleUserId, value: v)
            } else {
                Keychain.delete(key: Keychain.Keys.appleUserId)
            }
        }
    }

    var isAuthenticated: Bool { currentUserId != nil }

    private init() {
        migrateUserDefaultsToKeychainIfNeeded()
    }

    // MARK: - UserDefaults -> Keychain migration

    /// If the pre-Keychain build wrote the user id / email to `UserDefaults`,
    /// copy them into the Keychain on first launch of the new build.
    /// We deliberately leave the `UserDefaults` entries in place so legacy
    /// callers (e.g. any reads we missed) keep working during the transition.
    private func migrateUserDefaultsToKeychainIfNeeded() {
        let defaults = UserDefaults.standard
        if Keychain.load(key: Keychain.Keys.userId) == nil,
           let legacyId = defaults.string(forKey: "statshot_user_id"),
           !legacyId.isEmpty {
            Keychain.save(key: Keychain.Keys.userId, value: legacyId)
        }
        if Keychain.load(key: Keychain.Keys.userEmail) == nil,
           let legacyEmail = defaults.string(forKey: "statshot_user_email"),
           !legacyEmail.isEmpty {
            Keychain.save(key: Keychain.Keys.userEmail, value: legacyEmail)
        }
    }

    // MARK: - Sign in with Apple

    /// Drives the native SIWA flow. Returns the backend userId on success.
    /// Throws `AuthError.signInFailed` (wrapping the underlying
    /// `ASAuthorizationError` or network error) on failure.
    @MainActor
    func signInWithApple() async throws -> String {
        let credential = try await SIWAPresenter.shared.requestCredential()

        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw AuthError.signInFailed(
                underlying: NSError(
                    domain: "AuthService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing identity token"]
                )
            )
        }

        let appleUserId = credential.user
        let email = credential.email
        let fullName: APIService.AppleFullName? = {
            guard let name = credential.fullName else { return nil }
            return APIService.AppleFullName(
                givenName: name.givenName,
                familyName: name.familyName
            )
        }()

        let response = try await APIService.shared.signInWithApple(
            identityToken: identityToken,
            appleUserId: appleUserId,
            email: email,
            fullName: fullName
        )

        currentUserId = response.userId
        currentEmail = response.email
        currentAppleUserId = appleUserId

        // Fire-and-forget: if we've captured an APNs token already, send it
        // up under the new userId so pushes start flowing. The failure path
        // is handled by `refreshAPNsToken` on next launch.
        if let email = response.email,
           let token = NotificationService.shared.storedAPNsToken {
            Task {
                _ = try? await APIService.shared.register(
                    email: email,
                    apnsToken: token
                )
            }
        }

        return response.userId
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
        currentAppleUserId = nil
    }
}

// MARK: - SIWA presenter

/// Bridges `ASAuthorizationController`'s UIKit-style delegate callbacks into
/// an `async` function. Retains itself for the duration of a single request
/// via `activeRequest`; the UIKit delegate callbacks hop back to MainActor
/// before mutating state.
@MainActor
final class SIWAPresenter: NSObject {
    static let shared = SIWAPresenter()

    private var activeContinuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    /// Presents the SIWA sheet and awaits the result.
    func requestCredential() async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { continuation in
            // Only one in-flight SIWA request at a time. If a second call
            // arrives, fail it rather than stomping the first.
            if activeContinuation != nil {
                continuation.resume(
                    throwing: AuthError.signInFailed(
                        underlying: NSError(
                            domain: "AuthService",
                            code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "Sign in already in progress"]
                        )
                    )
                )
                return
            }
            activeContinuation = continuation

            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.email, .fullName]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func finish(with result: Result<ASAuthorizationAppleIDCredential, Error>) {
        guard let continuation = activeContinuation else { return }
        activeContinuation = nil
        switch result {
        case .success(let credential):
            continuation.resume(returning: credential)
        case .failure(let error):
            continuation.resume(throwing: AuthError.signInFailed(underlying: error))
        }
    }
}

extension SIWAPresenter: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                self.finish(with: .success(credential))
            } else {
                self.finish(
                    with: .failure(NSError(
                        domain: "AuthService",
                        code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "Unexpected credential type"]
                    ))
                )
            }
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            self.finish(with: .failure(error))
        }
    }
}

extension SIWAPresenter: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        // ASPresentationAnchor == UIWindow on iOS. Pull the first foreground
        // active window; fall back to a fresh UIWindow if none (shouldn't
        // happen once the app has finished launching).
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
                ?? ASPresentationAnchor()
        }
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
