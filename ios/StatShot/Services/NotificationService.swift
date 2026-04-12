import Foundation
import UserNotifications

/// Handles APNs push notification registration and permission requests.
/// Sends device token to the Vercel backend for direct APNs delivery.
final class NotificationService: NSObject, @unchecked Sendable {
    static let shared = NotificationService()

    private override init() {
        super.init()
    }

    /// Registers this service as the `UNUserNotificationCenter` delegate so
    /// foreground push notifications present a banner, play sound, and update
    /// the badge instead of being silently dropped by iOS.
    func registerDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    // TODO: Uncomment when running on a real device
                    // UIApplication.shared.registerForRemoteNotifications()
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
    }

    var storedAPNsToken: String? {
        UserDefaults.standard.string(forKey: "statshot_apns_token")
    }
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
