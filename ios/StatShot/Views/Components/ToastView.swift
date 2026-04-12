import SwiftUI

/// Lightweight transient banner shown above the app's content when something
/// non-blocking goes wrong (e.g. a deep link can't resolve). The parent view
/// is responsible for mounting, animating in/out, and dismissing after a
/// timeout; this view just renders a message.
struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .shadow(radius: 8)
    }
}
