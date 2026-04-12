import UIKit
import UserNotifications

/// UIKit adaptor that receives APNs lifecycle callbacks which SwiftUI's
/// scene-based lifecycle does not surface. Installed via
/// `@UIApplicationDelegateAdaptor` in `StatShotApp`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Install the notification center delegate here — earlier in the launch
        // lifecycle than any SwiftUI `.task`, so cold-start notification taps
        // are not dropped.
        UNUserNotificationCenter.current().delegate = NotificationService.shared
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        NotificationService.shared.handleDeviceToken(deviceToken)
        // If the user is already signed in, push the fresh token to the backend.
        Task { @MainActor in
            await AuthService.shared.refreshAPNsToken()
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed to register for remote notifications: \(error)")
    }
}
