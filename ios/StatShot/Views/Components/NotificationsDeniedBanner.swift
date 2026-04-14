import SwiftUI
import UIKit

/// Persistent, dismissible banner shown at the top of HomeView when the user
/// has denied the iOS notification permission. Without this, the product
/// silently breaks — no pushes will ever arrive. Tapping "Open Settings"
/// deep-links into the app's iOS settings page so the user can flip the
/// toggle back on; the `.active` ScenePhase observer in `ContentView` picks
/// up the change on return.
///
/// Dismissal is session-scoped: the parent (`HomeView`) holds the `@State`
/// that hides this view, so re-launching the app re-shows the banner if the
/// status is still `.denied`.
struct NotificationsDeniedBanner: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Notifications are off")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Turn them on in Settings to receive alerts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            Spacer(minLength: 0)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(14)
        .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
}
