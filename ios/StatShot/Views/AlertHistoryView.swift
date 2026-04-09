import SwiftUI

struct AlertHistoryView: View {
    @State private var viewModel = AlertHistoryViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading history...")
                } else if viewModel.alerts.isEmpty {
                    ContentUnavailableView {
                        Label("No Alerts Yet", systemImage: "clock")
                    } description: {
                        Text("Alerts will appear here when your subscriptions trigger.")
                    }
                } else {
                    alertList
                }
            }
            .navigationTitle("History")
            .task {
                await viewModel.loadAlerts()
            }
        }
    }

    private var alertList: some View {
        List(viewModel.alerts) { alert in
            VStack(alignment: .leading, spacing: 6) {
                Text(alert.message)
                    .font(.body)

                HStack {
                    Image(systemName: alert.deliveryMethod == "sms" ? "message.fill" : "bell.fill")
                        .font(.caption2)
                    Text(alert.sentAt, style: .relative)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}
