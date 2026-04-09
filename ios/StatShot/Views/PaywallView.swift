import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    featuresComparison
                    purchaseButton
                    restoreButton
                }
                .padding()
            }
            .navigationTitle("Go Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.yellow)

            Text("StatShot Premium")
                .font(.title)
                .fontWeight(.bold)

            Text("Never miss a moment")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top)
    }

    private var featuresComparison: some View {
        VStack(spacing: 12) {
            featureRow("Unlimited alerts", free: "3 max", premium: "Unlimited")
            featureRow("Push notifications", free: true, premium: true)
            featureRow("SMS alerts", free: false, premium: true)
            featureRow("Alert history", free: "7 days", premium: "90 days")
            featureRow("All sports & triggers", free: true, premium: true)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func featureRow(_ feature: String, free: Any, premium: Any) -> some View {
        HStack {
            Text(feature)
                .font(.subheadline)

            Spacer()

            Group {
                if let boolVal = free as? Bool {
                    Image(systemName: boolVal ? "checkmark" : "xmark")
                        .foregroundStyle(boolVal ? .green : .red)
                } else {
                    Text(String(describing: free))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 70)

            Group {
                if let boolVal = premium as? Bool {
                    Image(systemName: boolVal ? "checkmark" : "xmark")
                        .foregroundStyle(boolVal ? .green : .red)
                } else {
                    Text(String(describing: premium))
                        .foregroundStyle(.accent)
                        .fontWeight(.medium)
                }
            }
            .frame(width: 70)
        }
    }

    private var purchaseButton: some View {
        Button {
            Task { await purchase() }
        } label: {
            HStack {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Subscribe for $4.99/month")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.accent, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
        }
        .disabled(isPurchasing)
    }

    private var restoreButton: some View {
        Button("Restore Purchases") {
            // TODO: Restore Stripe/StoreKit purchases
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func purchase() async {
        isPurchasing = true
        defer { isPurchasing = false }

        // TODO: Stripe payment sheet integration
    }
}
