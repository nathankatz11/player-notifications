import SwiftUI

struct AlertHistoryView: View {
    @State private var viewModel = AlertHistoryViewModel()
    @State private var hasAppeared = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading history...")
                } else if viewModel.alerts.isEmpty {
                    emptyState
                } else {
                    alertScrollView
                }
            }
            .navigationTitle("History")
            .task {
                await viewModel.loadAlerts()
                withAnimation(.easeOut(duration: 0.4)) {
                    hasAppeared = true
                }
            }
            .refreshable {
                hasAppeared = false
                await viewModel.loadAlerts()
                withAnimation(.easeOut(duration: 0.4)) {
                    hasAppeared = true
                }
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
                            AlertHistoryCard(alert: alert)
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
        }
        .scrollContentBackground(.hidden)
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

    var body: some View {
        HStack(spacing: 14) {
            Text(sportEmoji)
                .font(.system(size: 24))
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(alert.message)
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(3)

                HStack(spacing: 6) {
                    Image(systemName: alert.deliveryMethod == "sms" ? "message.fill" : "bell.fill")
                        .font(.caption2)
                        .foregroundStyle(isRecent ? Color.accentColor : .secondary)
                    Text(relativeTimeString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if isRecent {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Alerts from the last 10 minutes are considered "live/recent"
    private var isRecent: Bool {
        alert.sentAt.timeIntervalSinceNow > -600
    }

    /// Parse sport emoji from the first character of the message
    private var sportEmoji: String {
        guard let first = alert.message.first else { return "\u{1F514}" }
        let firstStr = String(first)
        if firstStr.unicodeScalars.first?.properties.isEmoji == true,
           first.isWholeNumber == false, first != "#", first != "*" {
            return firstStr
        }
        return "\u{1F514}"
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
