import SwiftUI

struct AddAlertView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = SubscriptionViewModel()

    @State private var selectedLeague: League = .nba
    @State private var selectedTrigger: TriggerType?
    @State private var selectedEntity: SearchResult?
    @State private var deliveryMethod: DeliveryMethod = .push

    var body: some View {
        NavigationStack {
            Form {
                leagueSection
                searchSection
                triggerSection
                deliverySection
                createSection
            }
            .navigationTitle("New Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var leagueSection: some View {
        Section("League") {
            Picker("League", selection: $selectedLeague) {
                ForEach(League.allCases) { league in
                    Label(league.displayName, systemImage: league.icon)
                        .tag(league)
                }
            }
            .pickerStyle(.navigationLink)
        }
    }

    private var searchSection: some View {
        Section("Player or Team") {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search players or teams...", text: $viewModel.searchQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .onChange(of: viewModel.searchQuery) {
                Task { await viewModel.searchEntities() }
            }

            if viewModel.isSearching {
                ProgressView()
            }

            ForEach(viewModel.searchResults) { result in
                Button {
                    selectedEntity = result
                    viewModel.searchQuery = result.name
                    viewModel.searchResults = []
                } label: {
                    HStack {
                        Text(result.name)
                        Spacer()
                        Text(result.type)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let entity = selectedEntity {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(entity.name)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var triggerSection: some View {
        Section("Alert When") {
            ForEach(selectedLeague.triggers, id: \.self) { trigger in
                Button {
                    selectedTrigger = trigger
                } label: {
                    HStack {
                        Text(trigger.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedTrigger == trigger {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
    }

    private var deliverySection: some View {
        Section("Delivery") {
            Picker("Method", selection: $deliveryMethod) {
                ForEach(DeliveryMethod.allCases) { method in
                    Text(method.displayName).tag(method)
                }
            }

            if deliveryMethod != .push {
                Text("SMS requires a Premium subscription")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var createSection: some View {
        Section {
            Button {
                Task { await createAlert() }
            } label: {
                HStack {
                    Spacer()
                    Text("Create Alert")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(selectedEntity == nil || selectedTrigger == nil)
        }
    }

    private func createAlert() async {
        guard let entity = selectedEntity, let trigger = selectedTrigger else { return }

        await viewModel.createSubscription(
            type: .playerStat,
            league: selectedLeague,
            entityId: entity.id,
            entityName: entity.name,
            trigger: trigger,
            deliveryMethod: deliveryMethod
        )

        dismiss()
    }
}
