import SwiftUI

struct AlertHistoryView: View {
    @State private var viewModel = AlertHistoryViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading history...")
                } else if viewModel.alerts.isEmpty {
                    emptyState
                } else {
                    alertList
                }
            }
            .navigationTitle("History")
            .task {
                await viewModel.loadAlerts()
            }
            .refreshable {
                await viewModel.loadAlerts()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Alerts Yet", systemImage: "bell.badge.clock")
        } description: {
            Text("Your alerts will show up here when games are live and your subscriptions match.")
        }
    }

    // MARK: - Grouped Alert List

    private var alertList: some View {
        List {
            ForEach(groupedAlerts, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.alerts) { alert in
                        AlertHistoryRow(alert: alert)
                    }
                }
            }
        }
    }

    private var groupedAlerts: [AlertSection] {
        let calendar = Calendar.current

        var todayAlerts: [AlertItem] = []
        var yesterdayAlerts: [AlertItem] = []
        var earlierAlerts: [AlertItem] = []

        for alert in viewModel.alerts {
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
}

// MARK: - Section Model

private struct AlertSection {
    let title: String
    let alerts: [AlertItem]
}

// MARK: - Alert Row

private struct AlertHistoryRow: View {
    let alert: AlertItem

    var body: some View {
        HStack(spacing: 12) {
            // Colored left accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(isRecent ? Color.red : Color.secondary.opacity(0.3))
                .frame(width: 4, height: 44)

            // Sport emoji
            Text(sportEmoji)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(alert.message)
                    .font(.body)

                HStack(spacing: 6) {
                    Image(systemName: alert.deliveryMethod == "sms" ? "message.fill" : "bell.fill")
                        .font(.caption2)
                    Text(relativeTimeString)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// Alerts from the last 10 minutes are considered "live/recent"
    private var isRecent: Bool {
        alert.sentAt.timeIntervalSinceNow > -600
    }

    /// Parse sport emoji from the first character of the message
    private var sportEmoji: String {
        guard let first = alert.message.first else { return "🔔" }
        let firstStr = String(first)
        // If the message already starts with an emoji, use it
        if firstStr.unicodeScalars.first?.properties.isEmoji == true,
           first.isWholeNumber == false, first != "#", first != "*" {
            return firstStr
        }
        return "🔔"
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
