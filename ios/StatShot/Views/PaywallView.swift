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
            featureRow("Unlimited alerts", freeText: "3 max", premiumText: "Unlimited")
            featureRow("Push notifications", freeCheck: true, premiumCheck: true)
            featureRow("SMS alerts", freeCheck: false, premiumCheck: true)
            featureRow("Alert history", freeText: "7 days", premiumText: "90 days")
            featureRow("All sports & triggers", freeCheck: true, premiumCheck: true)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func featureRow(_ feature: String, freeText: String, premiumText: String) -> some View {
        HStack {
            Text(feature).font(.subheadline)
            Spacer()
            Text(freeText).foregroundStyle(.secondary).frame(width: 70)
            Text(premiumText).foregroundStyle(.tint).fontWeight(.medium).frame(width: 70)
        }
    }

    private func featureRow(_ feature: String, freeCheck: Bool, premiumCheck: Bool) -> some View {
        HStack {
            Text(feature).font(.subheadline)
            Spacer()
            Image(systemName: freeCheck ? "checkmark" : "xmark")
                .foregroundStyle(freeCheck ? .green : .red)
                .frame(width: 70)
            Image(systemName: premiumCheck ? "checkmark" : "xmark")
                .foregroundStyle(premiumCheck ? .green : .red)
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
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
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
