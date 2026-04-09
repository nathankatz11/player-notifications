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
                teamPickerSection
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
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .task {
                await viewModel.loadTeams()
            }
            .onChange(of: selectedLeague) {
                viewModel.selectedLeague = selectedLeague
                selectedEntity = nil
                Task { await viewModel.loadTeams() }
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

    private var teamPickerSection: some View {
        Section("Select a Team") {
            if viewModel.isLoadingTeams {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if viewModel.teams.isEmpty {
                Text("No teams available")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.teams) { team in
                    Button {
                        selectedEntity = SearchResult(
                            id: team.id,
                            name: team.name,
                            type: "team",
                            imageUrl: team.logoUrl
                        )
                        viewModel.searchQuery = ""
                        viewModel.searchResults = []
                    } label: {
                        HStack(spacing: 10) {
                            AsyncImage(url: team.logoUrl.flatMap { URL(string: $0) }) { image in
                                image
                                    .resizable()
                                    .scaledToFit()
                            } placeholder: {
                                Text(team.abbreviation)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())

                            Text(team.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(team.abbreviation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if selectedEntity?.id == team.id && selectedEntity?.type == "team" {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
        }
    }

    private var searchSection: some View {
        Section("Or Search Players") {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search players...", text: $viewModel.searchQuery)
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
                            .foregroundStyle(.primary)
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
                    Spacer()
                    Text(entity.type)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

        let subscriptionType: SubscriptionType = entity.type == "team" ? .teamEvent : .playerStat

        await viewModel.createSubscription(
            type: subscriptionType,
            league: selectedLeague,
            entityId: entity.id,
            entityName: entity.name,
            trigger: trigger,
            deliveryMethod: deliveryMethod
        )

        dismiss()
    }
}
