import Foundation
import UIKit
import UserNotifications

/// Handles APNs push notification registration and permission requests.
/// Sends device token to the Vercel backend for direct APNs delivery.
final class NotificationService: NSObject, @unchecked Sendable {
    static let shared = NotificationService()

    /// One-shot resolvers awaiting the next APNs device token. Mutated only on
    /// the main actor (see `awaitDeviceToken` and `handleDeviceToken`).
    @MainActor
    private var tokenResolvers: [(String) -> Void] = []

    private override init() {
        super.init()
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }

            if let error {
                print("Notification authorization error: \(error)")
            }
        }
    }

    func handleDeviceToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("APNs device token: \(token)")

        // Store locally and send to backend on next register/login
        UserDefaults.standard.set(token, forKey: "statshot_apns_token")

        // Notify any awaiters that were blocked waiting for the token.
        Task { @MainActor in
            let resolvers = tokenResolvers
            tokenResolvers.removeAll()
            for resolver in resolvers {
                resolver(token)
            }
        }
    }

    var storedAPNsToken: String? {
        UserDefaults.standard.string(forKey: "statshot_apns_token")
    }

    /// Waits up to `timeout` for iOS to deliver an APNs device token. Returns
    /// the cached token immediately if one is already present. On simulator
    /// (where APNs never calls back) this resolves to `nil` after the timeout
    /// and the caller should fall back to a placeholder.
    @MainActor
    func awaitDeviceToken(timeout: Duration = .seconds(3)) async -> String? {
        if let token = storedAPNsToken { return token }

        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            // `resumed` is only touched on the main actor, both by the resolver
            // (invoked from `handleDeviceToken`'s main-actor hop) and by the
            // timeout task below (also hops to the main actor). No lock needed.
            let state = ResumeState()

            tokenResolvers.append { token in
                guard !state.resumed else { return }
                state.resumed = true
                continuation.resume(returning: token)
            }

            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                guard !state.resumed else { return }
                state.resumed = true
                continuation.resume(returning: nil)
            }
        }
    }
}

/// Main-actor-isolated one-shot guard for `awaitDeviceToken`'s continuation.
@MainActor
private final class ResumeState {
    var resumed = false
}

extension NotificationService: UNUserNotificationCenterDelegate {
    /// Called when a notification arrives while the app is in the foreground.
    /// Returning `[.banner, .sound, .badge, .list]` makes iOS present the
    /// notification as if the app were in the background.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }

    /// Called when the user taps (or otherwise interacts with) a notification.
    /// If the APNs payload carries a `subscriptionId` custom field, hand it to
    /// `DeepLinkCoordinator` so the Alerts tab can navigate to the matching
    /// `AlertDetailView`. Works for cold start too — the coordinator retains
    /// the id until a view mounts and consumes it.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let subscriptionId = userInfo["subscriptionId"] as? String

        if let subscriptionId, !subscriptionId.isEmpty {
            Task { @MainActor in
                DeepLinkCoordinator.shared.request(subscriptionId: subscriptionId)
            }
        } else {
            print("Notification tapped (no subscriptionId): \(userInfo)")
        }

        completionHandler()
    }
}
