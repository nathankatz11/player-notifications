import SwiftUI

struct AddAlertView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = SubscriptionViewModel()

    private let initialLeague: League?

    @State private var selectedLeague: League = .nba
    @State private var selectedTrigger: TriggerType?
    @State private var selectedEntity: SearchResult?
    @State private var deliveryMethod: DeliveryMethod = .push
    @State private var teamFilter = ""
    @State private var showSuccess = false
    @State private var isTeamSectionExpanded = false

    init(initialLeague: League? = nil) {
        self.initialLeague = initialLeague
        if let league = initialLeague {
            _selectedLeague = State(initialValue: league)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                leagueSection
                trendingSection
                playerSearchSection
                teamPickerSection
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
            .overlay {
                if showSuccess {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.green)
                        Text("Alert Created")
                            .font(.headline)
                    }
                    .padding(32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showSuccess)
            .task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await self.viewModel.loadTeams() }
                    group.addTask { await self.viewModel.loadTrending() }
                }
            }
            .onChange(of: selectedLeague) {
                viewModel.selectedLeague = selectedLeague
                selectedEntity = nil
                Task {
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask { await self.viewModel.loadTeams() }
                        group.addTask { await self.viewModel.loadTrending() }
                    }
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

    private var filteredTeams: [Team] {
        guard !teamFilter.isEmpty else { return viewModel.teams }
        let query = teamFilter.lowercased()
        return viewModel.teams.filter {
            $0.name.lowercased().contains(query) ||
            $0.abbreviation.lowercased().contains(query)
        }
    }

    // MARK: - Trending

    @ViewBuilder
    private var trendingSection: some View {
        if !viewModel.trendingPlayers.isEmpty && selectedEntity == nil {
            Section("Trending Now") {
                ForEach(viewModel.trendingPlayers) { player in
                    Button {
                        selectedEntity = SearchResult(
                            id: player.id,
                            name: player.name,
                            type: "player",
                            imageUrl: nil
                        )
                        viewModel.searchQuery = player.name
                        viewModel.searchResults = []
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.fill")
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(player.name)
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(.primary)
                                Text(player.team)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Text("\u{1F525}")
                                    .font(.caption)
                                Text("\(player.plays)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    // MARK: - Player Search (Primary)

    private var playerSearchSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.accentColor)
                    .font(.title3)
                TextField("Search for a player...", text: $viewModel.searchQuery)
                    .font(.body)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                        viewModel.searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .onChange(of: viewModel.searchQuery) {
                Task { await viewModel.searchEntities() }
            }

            if viewModel.isSearching {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }

            if viewModel.searchQuery.isEmpty && !viewModel.isSearching && viewModel.searchResults.isEmpty && selectedEntity == nil {
                Text("Try: LeBron James, Patrick Mahomes, Connor McDavid...")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }

            ForEach(viewModel.searchResults) { result in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    selectedEntity = result
                    viewModel.searchQuery = result.name
                    viewModel.searchResults = []
                } label: {
                    if result.type == "player" {
                        HStack(spacing: 10) {
                            Image(systemName: "person.fill")
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 24)
                            Text(result.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedEntity?.id == result.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "shield.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            Text(result.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Team")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }

            if let entity = selectedEntity {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(entity.name)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(entity.type == "player" ? "Player" : "Team")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        selectedEntity = nil
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Find a Player")
        }
    }

    // MARK: - Team Picker (Secondary, collapsed)

    private var teamPickerSection: some View {
        Section {
            DisclosureGroup("Or Pick a Team", isExpanded: $isTeamSectionExpanded) {
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
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Filter teams...", text: $teamFilter)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !teamFilter.isEmpty {
                            Button {
                                teamFilter = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    ForEach(filteredTeams) { team in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
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
    }

    private var triggerSection: some View {
        Section("Alert When") {
            ForEach(selectedLeague.triggers, id: \.self) { trigger in
                Button {
                    selectedTrigger = trigger
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(trigger.displayName)
                                .foregroundStyle(.primary)
                            Text(trigger.triggerDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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

        guard viewModel.errorMessage == nil else { return }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showSuccess = true
        try? await Task.sleep(for: .milliseconds(800))
        dismiss()
    }
}
