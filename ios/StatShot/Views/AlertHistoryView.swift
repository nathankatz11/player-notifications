import SwiftUI
import UIKit

struct AlertHistoryView: View {
    @State private var viewModel = AlertHistoryViewModel()
    @State private var hasAppeared = false
    @State private var showingAddAlert = false
    @State private var deepLinkTarget: Subscription?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading history...")
                } else if viewModel.alerts.isEmpty {
                    emptyState
                } else if viewModel.filteredAlerts.isEmpty {
                    filteredEmptyState
                } else {
                    alertScrollView
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu
                }
            }
            .task {
                await viewModel.loadAlerts()
                withAnimation(.easeOut(duration: 0.4)) {
                    hasAppeared = true
                }
                try? await Task.sleep(for: .seconds(1))
                viewModel.markAllAsSeen()
                // Cold-start / first-mount: pick up any deep link that was
                // queued before this view appeared.
                await consumePendingDeepLink()
            }
            .refreshable {
                hasAppeared = false
                await viewModel.loadAlerts()
                withAnimation(.easeOut(duration: 0.4)) {
                    hasAppeared = true
                }
                try? await Task.sleep(for: .seconds(1))
                viewModel.markAllAsSeen()
            }
            .sheet(isPresented: $showingAddAlert) {
                AddAlertView()
            }
            .navigationDestination(item: $deepLinkTarget) { sub in
                AlertDetailView(subscription: sub)
            }
            .onChange(of: DeepLinkCoordinator.shared.pendingSubscriptionId) { _, newValue in
                guard newValue != nil else { return }
                Task { await consumePendingDeepLink() }
            }
        }
    }

    // MARK: - Deep Linking

    /// Resolves a pending deep-link subscription id into a local `Subscription`
    /// and pushes `AlertDetailView`. If the subscription map hasn't been
    /// populated yet, reloads alerts once and retries before giving up.
    private func consumePendingDeepLink() async {
        guard let pendingId = DeepLinkCoordinator.shared.pendingSubscriptionId else {
            return
        }

        if let match = viewModel.subscriptionsById[pendingId] {
            _ = DeepLinkCoordinator.shared.consume()
            deepLinkTarget = match
            return
        }

        await viewModel.loadAlerts()
        if let match = viewModel.subscriptionsById[pendingId] {
            _ = DeepLinkCoordinator.shared.consume()
            deepLinkTarget = match
        } else {
            // Couldn't resolve — surface a toast and clear so we don't loop
            // forever.
            DeepLinkCoordinator.shared.reportFailure("This alert's subscription is no longer available.")
            _ = DeepLinkCoordinator.shared.consume()
        }
    }

    // MARK: - Filter Menu

    private var filterMenu: some View {
        Menu {
            Section("League") {
                Button {
                    viewModel.clearLeagueFilter()
                } label: {
                    if viewModel.selectedLeagues.isEmpty {
                        Label("All Leagues", systemImage: "checkmark")
                    } else {
                        Text("All Leagues")
                    }
                }

                ForEach(League.allCases) { league in
                    Button {
                        viewModel.toggleLeague(league)
                    } label: {
                        if viewModel.selectedLeagues.contains(league) {
                            Label(league.displayName, systemImage: "checkmark")
                        } else {
                            Text(league.displayName)
                        }
                    }
                }
            }

            if viewModel.isFilterActive {
                Section {
                    Text("\(viewModel.selectedLeagues.count) \(viewModel.selectedLeagues.count == 1 ? "league" : "leagues") selected")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: viewModel.isFilterActive
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
                    .foregroundStyle(viewModel.isFilterActive ? Color.orange : Color.accentColor)

                if viewModel.isFilterActive {
                    Text("\(viewModel.selectedLeagues.count)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange, in: Capsule())
                }
            }
            .accessibilityLabel(viewModel.isFilterActive
                                ? "Filter active, \(viewModel.selectedLeagues.count) leagues selected"
                                : "Filter")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Alerts Yet", systemImage: "bell.badge.clock")
        } description: {
            Text("Your alerts will show up here when games are live and your subscriptions match.")
        } actions: {
            Button {
                showingAddAlert = true
            } label: {
                Text("Create an alert").fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
    }

    private var filteredEmptyState: some View {
        ContentUnavailableView {
            Label("No alerts match", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("Try clearing your league filter.")
        } actions: {
            Button {
                viewModel.clearLeagueFilter()
            } label: {
                Text("Clear filter").fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
    }

    // MARK: - Scroll View with Cards

    private var alertScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                let sections = groupedAlerts
                ForEach(Array(sections.enumerated()), id: \.element.title) { sectionIndex, section in
                    Section {
                        ForEach(Array(section.alerts.enumerated()), id: \.element.id) { rowIndex, alert in
                            let globalIndex = globalOffset(
                                forSection: sectionIndex,
                                row: rowIndex,
                                sections: sections
                            )
                            let sub = viewModel.subscription(for: alert)
                            let unread = viewModel.isUnread(alert)

                            Group {
                                if let sub {
                                    NavigationLink {
                                        AlertDetailView(subscription: sub)
                                    } label: {
                                        AlertHistoryCard(
                                            alert: alert,
                                            subscription: sub,
                                            isUnread: unread
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        muteSwipeButton(for: sub)
                                        ShareLink(item: alert.message) {
                                            Label("Share", systemImage: "square.and.arrow.up")
                                        }
                                        .tint(.blue)
                                    }
                                } else {
                                    AlertHistoryCard(
                                        alert: alert,
                                        subscription: nil,
                                        isUnread: unread
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                            .opacity(hasAppeared ? 1 : 0)
                            .offset(y: hasAppeared ? 0 : 20)
                            .animation(
                                .easeOut(duration: 0.35)
                                    .delay(Double(globalIndex) * 0.05),
                                value: hasAppeared
                            )
                        }
                    } header: {
                        sectionHeader(section.title)
                    }
                }
            }
            .padding(.vertical, 8)

            // Pagination footer — appears after the last section.
            // The trailing 1pt transparent view acts as a scroll sentinel:
            // when it enters the viewport, we fetch the next page.
            if viewModel.hasMore {
                HStack {
                    Spacer()
                    if viewModel.isLoadingMore {
                        ProgressView()
                    } else {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                Task { await viewModel.loadMore() }
                            }
                    }
                    Spacer()
                }
                .padding()
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Swipe Action Buttons

    @ViewBuilder
    private func muteSwipeButton(for sub: Subscription) -> some View {
        if sub.active {
            Button {
                Task {
                    let result = await viewModel.setSubscriptionActive(sub, active: false)
                    await MainActor.run {
                        if result != nil {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } else {
                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                        }
                    }
                }
            } label: {
                Label("Mute", systemImage: "bell.slash.fill")
            }
            .tint(.orange)
        } else {
            Button {
                Task {
                    let result = await viewModel.setSubscriptionActive(sub, active: true)
                    await MainActor.run {
                        if result != nil {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } else {
                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                        }
                    }
                }
            } label: {
                Label("Unmute", systemImage: "bell.fill")
            }
            .tint(.orange)
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title.uppercased())
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .tracking(0.8)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 16)
        }
        .background(.background)
    }

    // MARK: - Date Grouping

    private var groupedAlerts: [AlertSection] {
        let calendar = Calendar.current

        var todayAlerts: [AlertItem] = []
        var yesterdayAlerts: [AlertItem] = []
        var earlierAlerts: [AlertItem] = []

        for alert in viewModel.filteredAlerts {
            if calendar.isDateInToday(alert.sentAt) {
                todayAlerts.append(alert)
            } else if calendar.isDateInYesterday(alert.sentAt) {
                yesterdayAlerts.append(alert)
            } else {
                earlierAlerts.append(alert)
            }
        }

        var sections: [AlertSection] = []
        if !todayAlerts.isEmpty {
            sections.append(AlertSection(title: "Today", alerts: todayAlerts))
        }
        if !yesterdayAlerts.isEmpty {
            sections.append(AlertSection(title: "Yesterday", alerts: yesterdayAlerts))
        }
        if !earlierAlerts.isEmpty {
            sections.append(AlertSection(title: "Earlier", alerts: earlierAlerts))
        }
        return sections
    }

    /// Computes the global row index across all sections for staggered animation delay.
    private func globalOffset(forSection sectionIndex: Int, row: Int, sections: [AlertSection]) -> Int {
        var offset = 0
        for i in 0..<sectionIndex {
            offset += sections[i].alerts.count
        }
        return offset + row
    }
}

// MARK: - Section Model

private struct AlertSection {
    let title: String
    let alerts: [AlertItem]
}

// MARK: - Alert Card

private struct AlertHistoryCard: View {
    let alert: AlertItem
    let subscription: Subscription?
    let isUnread: Bool

    private var leagueColor: Color {
        subscription?.league.color ?? .accentColor
    }

    private var entityName: String {
        subscription?.entityName ?? "Alert"
    }

    var body: some View {
        HStack(spacing: 14) {
            avatar
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(entityName)
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if isUnread {
                        Text("NEW")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(leagueColor, in: Capsule())
                    }

                    Spacer(minLength: 0)
                }

                HStack(alignment: .top, spacing: 6) {
                    if let sub = subscription {
                        Text(sub.trigger.shortLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(leagueColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(leagueColor.opacity(0.15), in: Capsule())
                    }

                    Text(alert.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Image(systemName: deliveryIcon)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(relativeTimeString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if subscription != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.11))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isUnread ? leagueColor : Color.clear, lineWidth: 2)
        )
    }

    // MARK: - Avatar

    @ViewBuilder
    private var avatar: some View {
        if let sub = subscription {
            ZStack {
                Circle()
                    .strokeBorder(sub.league.color, lineWidth: 2)
                    .frame(width: 44, height: 44)

                avatarImage(for: sub)
                    .frame(width: 38, height: 38)
                    .clipShape(Circle())
            }
        } else {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "bell.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func avatarImage(for sub: Subscription) -> some View {
        if sub.type == .playerStat,
           let url = League.playerHeadshotURL(espnId: sub.entityId, league: sub.league, size: 96) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    fallbackIcon(for: sub)
                }
            }
        } else if sub.type == .teamEvent,
                  let url = League.teamLogoURL(espnId: sub.entityId, league: sub.league) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                default:
                    fallbackIcon(for: sub)
                }
            }
        } else {
            fallbackIcon(for: sub)
        }
    }

    private func fallbackIcon(for sub: Subscription) -> some View {
        Circle()
            .fill(sub.league.color.opacity(0.15))
            .overlay {
                Image(systemName: sub.league.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(sub.league.color)
            }
    }

    // MARK: - Helpers

    private var deliveryIcon: String {
        switch alert.deliveryMethod {
        case "sms": "message.fill"
        case "tweet": "bird"
        default: "bell.fill"
        }
    }

    /// Human-friendly relative time: "Just now", "5m ago", "2h ago", etc.
    private var relativeTimeString: String {
        let elapsed = -alert.sentAt.timeIntervalSinceNow
        switch elapsed {
        case ..<60:
            return "Just now"
        case ..<3600:
            let minutes = Int(elapsed / 60)
            return "\(minutes)m ago"
        case ..<86400:
            let hours = Int(elapsed / 3600)
            return "\(hours)h ago"
        default:
            let days = Int(elapsed / 86400)
            return "\(days)d ago"
        }
    }
}
