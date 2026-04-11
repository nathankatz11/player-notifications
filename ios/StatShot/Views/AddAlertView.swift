import SwiftUI

struct AddAlertView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var viewModel = SubscriptionViewModel()

    private let initialLeague: League?

    @State private var selectedLeague: League = .nba
    @State private var selectedTrigger: TriggerType?
    @State private var selectedEntity: SearchResult?
    @State private var selectedDelivery: DeliveryMethod = .push
    @State private var contactInput: String = ""
    @State private var teamFilter = ""
    @State private var showSuccess = false

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
                if !viewModel.trendingPlayers.isEmpty && selectedEntity == nil && viewModel.searchQuery.isEmpty {
                    trendingSection
                }
                playerSearchSection
                if selectedEntity == nil || selectedEntity?.type == "team" {
                    teamPickerSection
                }
                triggerSection
                deliverySection
            }
            .navigationTitle("New Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await createAlert() }
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedEntity == nil || selectedTrigger == nil)
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
                selectedTrigger = nil
                teamFilter = ""
                viewModel.searchQuery = ""
                viewModel.searchResults = []
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
                    HStack(spacing: 8) {
                        AsyncImage(url: league.leagueLogoURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 22, height: 22)
                            default:
                                Image(systemName: league.icon)
                                    .frame(width: 22, height: 22)
                            }
                        }
                        Text(league.displayName)
                    }
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

    private var searchPlaceholder: String {
        switch selectedLeague {
        case .nba: "Try: LeBron James, Stephen Curry, Jayson Tatum..."
        case .nfl: "Try: Patrick Mahomes, Josh Allen, Derrick Henry..."
        case .nhl: "Try: Connor McDavid, Alex Ovechkin, Auston Matthews..."
        case .mlb: "Try: Aaron Judge, Shohei Ohtani, Mike Trout..."
        case .ncaafb: "Try: Carson Beck, Jalen Milroe, Shedeur Sanders..."
        case .ncaamb: "Try: Cooper Flagg, Dylan Harper, Ace Bailey..."
        case .mls: "Try: Lionel Messi, Lorenzo Insigne, Riqui Puig..."
        }
    }

    // MARK: - Trending

    private var trendingSection: some View {
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
                        if let url = League.playerHeadshotURL(espnId: player.id, league: selectedLeague, size: 36) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 36, height: 36)
                                        .clipShape(Circle())
                                default:
                                    Image(systemName: "person.fill")
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 36, height: 36)
                                }
                            }
                        } else {
                            Image(systemName: "person.fill")
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 36, height: 36)
                        }
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

    // MARK: - Player Search (Primary)

    private var playerSearchSection: some View {
        Section(header: Text("Find a \(selectedLeague.displayName) Player")) {
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
                Text(searchPlaceholder)
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
                            if let url = League.playerHeadshotURL(espnId: result.id, league: selectedLeague, size: 36) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 36, height: 36)
                                            .clipShape(Circle())
                                    default:
                                        Image(systemName: "person.fill")
                                            .foregroundStyle(Color.accentColor)
                                            .frame(width: 36, height: 36)
                                    }
                                }
                            } else {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 36, height: 36)
                            }
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
                            AsyncImage(url: result.imageUrl.flatMap { URL(string: $0) }) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 32, height: 32)
                                        .clipShape(Circle())
                                default:
                                    Image(systemName: "shield.fill")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 32, height: 32)
                                }
                            }
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
        }
    }

    // MARK: - Team Picker

    private var teamPickerSection: some View {
        Section("Or Pick a Team") {
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
        Section("Deliver Alert Via") {
            ForEach(DeliveryMethod.allCases) { method in
                Button {
                    selectedDelivery = method
                    // Pre-fill contact from saved profile
                    if method == .sms { contactInput = authViewModel.phone }
                    if method == .tweet { contactInput = authViewModel.xHandle }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: method.icon)
                            .foregroundStyle(selectedDelivery == method ? Color.accentColor : Color.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(method.displayName)
                                .foregroundStyle(.primary)
                            if method == .sms {
                                Text("Premium — we'll text you when it happens")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if method == .tweet {
                                Text("Premium — we'll tag any X handle when it happens")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if selectedDelivery == method {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            if selectedDelivery == .sms {
                HStack(spacing: 10) {
                    Image(systemName: "phone.fill")
                        .foregroundStyle(.green)
                        .frame(width: 20)
                    TextField("Phone number", text: $contactInput)
                        .keyboardType(.phonePad)
                        .autocorrectionDisabled()
                }
                .padding(.vertical, 2)
            }

            if selectedDelivery == .tweet {
                HStack(spacing: 10) {
                    Image(systemName: "bird")
                        .foregroundStyle(Color(red: 0.11, green: 0.63, blue: 0.95))
                        .frame(width: 20)
                    TextField("X handle to tag (yours or a friend's)", text: $contactInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.vertical, 2)
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

        // Save phone/X handle to profile if provided
        let trimmed = contactInput.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            if selectedDelivery == .sms {
                authViewModel.phone = trimmed
                await authViewModel.saveProfile()
            } else if selectedDelivery == .tweet {
                authViewModel.xHandle = trimmed
                await authViewModel.saveProfile()
            }
        }

        let subscriptionType: SubscriptionType = entity.type == "team" ? .teamEvent : .playerStat

        await viewModel.createSubscription(
            type: subscriptionType,
            league: selectedLeague,
            entityId: entity.id,
            entityName: entity.name,
            trigger: trigger,
            deliveryMethod: selectedDelivery
        )

        guard viewModel.errorMessage == nil else { return }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showSuccess = true
        try? await Task.sleep(for: .milliseconds(800))
        dismiss()
    }
}
