import SwiftUI

@MainActor
@Observable
final class AlertDetailViewModel {
    var alerts: [AlertItem] = []
    var isLoading = false
    var errorMessage: String?

    func loadAlerts(for subscriptionId: String) async {
        guard let userId = AuthService.shared.currentUserId else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await APIService.shared.getAlertHistory(userId: userId)
            alerts = page.alerts
                .filter { $0.subscriptionId == subscriptionId }
                .prefix(10)
                .map { $0 }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AlertDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AlertDetailViewModel()

    @State var subscription: Subscription
    @State private var selectedTrigger: TriggerType
    @State private var selectedDelivery: DeliveryMethod
    @State private var isActive: Bool
    @State private var showDeleteConfirmation = false

    var onDeleted: (() -> Void)?

    private var leagueColor: Color { subscription.league.color }

    init(subscription: Subscription, onDeleted: (() -> Void)? = nil) {
        self._subscription = State(initialValue: subscription)
        self._selectedTrigger = State(initialValue: subscription.trigger)
        self._selectedDelivery = State(initialValue: subscription.deliveryMethod)
        self._isActive = State(initialValue: subscription.active)
        self.onDeleted = onDeleted
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    toggleSection
                    recentAlertsSection
                    customizeSection
                    deleteSection
                }
                .padding(16)
            }
            .background(Color(white: 0.06))
            .navigationTitle("Alert Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await viewModel.loadAlerts(for: subscription.id)
            }
            .confirmationDialog(
                "Delete this alert?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Alert", role: .destructive) {
                    Task {
                        try? await APIService.shared.deleteSubscription(id: subscription.id)
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        onDeleted?()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove the alert for \(subscription.entityName).")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var isPlayerSubscription: Bool {
        subscription.type == .playerStat
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .strokeBorder(leagueColor, lineWidth: 6)
                    .frame(width: 120, height: 120)

                if isPlayerSubscription {
                    PlayerAvatar(
                        name: subscription.entityName,
                        espnId: subscription.entityId,
                        league: subscription.league,
                        storedURL: subscription.photoUrl,
                        size: 120
                    )
                    .frame(width: 108, height: 108)
                } else {
                    // Team subscriptions: show team logo
                    AsyncImage(url: League.teamLogoURL(espnId: subscription.entityId, league: subscription.league)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(width: 108, height: 108)
                                .clipShape(Circle())
                        default:
                            Circle()
                                .fill(leagueColor.opacity(0.15))
                                .frame(width: 108, height: 108)
                                .overlay {
                                    Image(systemName: subscription.league.icon)
                                        .font(.system(size: 44, weight: .medium))
                                        .foregroundStyle(leagueColor)
                                }
                        }
                    }
                }
            }

            Text(subscription.entityName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(subscription.trigger.triggerDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(subscription.league.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(leagueColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(leagueColor.opacity(0.15), in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(white: 0.11))
        )
    }

    // MARK: - Toggle

    private var toggleSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Alert Active")
                    .font(.headline)
                Text(isActive ? "Notifications are on" : "Notifications paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isActive)
                .tint(leagueColor)
                .labelsHidden()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.11))
        )
        .onChange(of: isActive) { _, newValue in
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task {
                try? await APIService.shared.updateSubscription(
                    id: subscription.id,
                    active: newValue
                )
                subscription.active = newValue
            }
        }
    }

    // MARK: - Recent Alerts

    private var recentAlertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Alerts")
                .font(.headline)
                .padding(.horizontal, 4)

            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if viewModel.alerts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bell.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No alerts fired yet")
                        .font(.subheadline.weight(.medium))
                    Text("This will light up during game time.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(white: 0.11))
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.alerts.enumerated()), id: \.element.id) { index, alert in
                        alertRow(alert)
                        if index < viewModel.alerts.count - 1 {
                            Divider()
                                .padding(.leading, 40)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(white: 0.11))
                )
            }
        }
    }

    private func alertRow(_ alert: AlertItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(sportEmoji)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.message)
                    .font(.subheadline)
                    .lineLimit(3)
                Text(alert.sentAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(12)
    }

    private var sportEmoji: String {
        switch subscription.league {
        case .nba, .ncaamb: "\u{1F3C0}"
        case .nfl, .ncaafb: "\u{1F3C8}"
        case .nhl: "\u{1F3D2}"
        case .mlb: "\u{26BE}"
        case .mls: "\u{26BD}"
        }
    }

    // MARK: - Customize

    private var customizeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Customize")
                .font(.headline)
                .padding(.horizontal, 4)

            // Trigger selection — chip grid instead of a plain Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Trigger")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(subscription.league.triggers) { trigger in
                        let isSelected = selectedTrigger == trigger
                        Button {
                            selectedTrigger = trigger
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.subheadline)
                                Text(trigger.displayName)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                isSelected
                                    ? leagueColor.opacity(0.2)
                                    : Color(white: 0.15),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(
                                        isSelected ? leagueColor : Color(white: 0.25),
                                        lineWidth: isSelected ? 1.5 : 0.5
                                    )
                            )
                            .foregroundStyle(isSelected ? leagueColor : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(white: 0.11))
            )

            // Delivery method — icon cards
            VStack(alignment: .leading, spacing: 8) {
                Text("Delivery")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                HStack(spacing: 10) {
                    ForEach(DeliveryMethod.allCases) { method in
                        let isSelected = selectedDelivery == method
                        Button {
                            selectedDelivery = method
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: method.icon)
                                    .font(.title3)
                                Text(method.displayName)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                isSelected
                                    ? leagueColor.opacity(0.2)
                                    : Color(white: 0.15),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .overlay(
                                isSelected
                                    ? RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(leagueColor, lineWidth: 1.5)
                                    : nil
                            )
                            .foregroundStyle(isSelected ? leagueColor : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(white: 0.11))
            )
        }
        .onChange(of: selectedTrigger) { _, newTrigger in
            Task {
                try? await APIService.shared.updateSubscription(
                    id: subscription.id,
                    updates: SubscriptionUpdate(trigger: newTrigger.rawValue)
                )
            }
        }
        .onChange(of: selectedDelivery) { _, newDelivery in
            Task {
                try? await APIService.shared.updateSubscription(
                    id: subscription.id,
                    updates: SubscriptionUpdate(deliveryMethod: newDelivery.rawValue)
                )
            }
        }
    }

    // MARK: - Delete

    private var deleteSection: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.body.weight(.semibold))
                Text("Delete Alert")
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 20)
    }
}
