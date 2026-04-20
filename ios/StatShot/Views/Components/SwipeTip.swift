import SwiftUI

/// A one-time dismissible tip banner explaining swipe gestures.
/// Stores its dismissed state in UserDefaults so it only shows once.
struct SwipeTip: View {
    let key: String

    @State private var dismissed: Bool

    init(key: String = "swipeTipDismissed") {
        self.key = key
        self._dismissed = State(initialValue: UserDefaults.standard.bool(forKey: key))
    }

    var body: some View {
        if !dismissed {
            HStack(spacing: 10) {
                Image(systemName: "hand.draw")
                    .font(.title3)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Swipe for quick actions")
                        .font(.subheadline.weight(.semibold))
                    Text("Swipe left to delete, right to pause or resume")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        dismissed = true
                    }
                    UserDefaults.standard.set(true, forKey: key)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.secondary.opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.orange.opacity(0.2), lineWidth: 0.5)
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}
