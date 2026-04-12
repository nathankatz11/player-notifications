import SwiftUI

/// Two-decision alert creation:
///   1. Who — unified player + team search (league inferred from the active filter).
///   2. What — tap a big trigger chip → creates the alert and dismisses.
///
/// Delivery method defaults to `.push`; users change it later from AlertDetailView.
struct AddAlertView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = SubscriptionViewModel()

    private let initialLeague: League?

    private enum Step {
        case search
        case trigger(SearchResult, League)
    }

    @State private var step: Step = .search
    @State private var selectedLeague: League = .nba
    @State private var isCreating = false
    @State private var showSuccess = false
    @State private var searchTask: Task<Void, Never>?
    @State private var leagueTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    init(initialLeague: League? = nil) {
        self.initialLeague = initialLeague
        if let league = initialLeague {
            _selectedLeague = State(initialValue: league)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .search:
                    searchStep
                case let .trigger(entity, league):
                    TriggerStep(
                        entity: entity,
                        league: league,
                        isCreating: isCreating,
                        onBack: {
                            step = .search
                            // Re-focus search field on return
                            DispatchQueue.main.async { searchFocused = true }
                        },
                        onPick: { trigger in
                            Task { await createAlert(entity: entity, league: league, trigger: trigger) }
                        }
                    )
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Close")
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
                viewModel.selectedLeague = selectedLeague
                await reloadForLeague()
            }
            .onChange(of: selectedLeague) { _, newValue in
                viewModel.selectedLeague = newValue
                viewModel.searchResults = []
                leagueTask?.cancel()
                leagueTask = Task {
                    await reloadForLeague()
                }
                // Re-run any in-flight query against the new league, debounced
                // and cancelable alongside keystroke-driven searches.
                if !viewModel.searchQuery.isEmpty {
                    searchTask?.cancel()
                    searchTask = Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        guard !Task.isCancelled else { return }
                        await viewModel.searchEntities()
                    }
                }
            }
        }
    }

    private var navTitle: String {
        switch step {
        case .search: "New Alert"
        case .trigger: "Alert me when…"
        }
    }

    private func reloadForLeague() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.viewModel.loadTeams() }
            group.addTask { await self.viewModel.loadTrending() }
        }
    }

    // MARK: - Step 1: Search

    private var searchStep: some View {
        VStack(spacing: 0) {
            leaguePills
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)

            searchField
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if viewModel.searchQuery.isEmpty {
                        quickPicks
                    } else {
                        searchResults
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .onAppear { searchFocused = true }
    }

    private var leaguePills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(League.allCases) { league in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        selectedLeague = league
                    } label: {
                        Text(league.shortName)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(
                                    selectedLeague == league
                                        ? league.color.opacity(0.25)
                                        : Color.secondary.opacity(0.12)
                                )
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    selectedLeague == league ? league.color : Color.clear,
                                    lineWidth: 1
                                )
                            )
                            .foregroundStyle(selectedLeague == league ? league.color : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search a player or team", text: $viewModel.searchQuery)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12))
        )
        .onChange(of: viewModel.searchQuery) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await viewModel.searchEntities()
            }
        }
    }

    // MARK: - Quick picks (empty query)

    @ViewBuilder
    private var quickPicks: some View {
        if !viewModel.trendingPlayers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Trending")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.trendingPlayers) { player in
                            Button {
                                pickTrendingPlayer(player)
                            } label: {
                                HStack(spacing: 6) {
                                    Text("\u{1F525}")
                                        .font(.caption)
                                    Text(player.name)
                                        .font(.subheadline.weight(.semibold))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(selectedLeague.color.opacity(0.18))
                                )
                                .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }

        if !viewModel.teams.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Popular Teams")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 110), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(viewModel.teams.prefix(12)) { team in
                        Button {
                            pickTeam(team)
                        } label: {
                            HStack(spacing: 8) {
                                teamLogo(team, size: 22)
                                Text(team.abbreviation)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.secondary.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        if viewModel.isLoadingTeams && viewModel.teams.isEmpty {
            HStack { Spacer(); ProgressView(); Spacer() }
        }
    }

    // MARK: - Search results (non-empty query)

    @ViewBuilder
    private var searchResults: some View {
        if viewModel.isSearching {
            HStack { Spacer(); ProgressView(); Spacer() }
                .padding(.top, 12)
        } else if viewModel.searchResults.isEmpty && viewModel.searchQuery.count >= 2 {
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("No matches in \(selectedLeague.shortName).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Try another league above.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        } else {
            VStack(spacing: 0) {
                ForEach(viewModel.searchResults) { result in
                    Button {
                        pickEntity(result)
                    } label: {
                        SearchRow(result: result, league: selectedLeague)
                    }
                    .buttonStyle(.plain)
                    if result.id != viewModel.searchResults.last?.id {
                        Divider().padding(.leading, 52)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func pickEntity(_ result: SearchResult) {
        UISelectionFeedbackGenerator().selectionChanged()
        searchFocused = false
        step = .trigger(result, selectedLeague)
    }

    private func pickTrendingPlayer(_ player: TrendingPlayer) {
        let result = SearchResult(
            id: player.id,
            name: player.name,
            type: "player",
            imageUrl: nil
        )
        pickEntity(result)
    }

    private func pickTeam(_ team: Team) {
        let result = SearchResult(
            id: team.id,
            name: team.name,
            type: "team",
            imageUrl: team.logoUrl
        )
        pickEntity(result)
    }

    private func createAlert(entity: SearchResult, league: League, trigger: TriggerType) async {
        guard !isCreating else { return }
        isCreating = true
        defer { isCreating = false }

        let subscriptionType: SubscriptionType = entity.type == "team" ? .teamEvent : .playerStat

        await viewModel.createSubscription(
            type: subscriptionType,
            league: league,
            entityId: entity.id,
            entityName: entity.name,
            trigger: trigger,
            deliveryMethod: .push
        )

        guard viewModel.errorMessage == nil else { return }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showSuccess = true
        try? await Task.sleep(for: .milliseconds(800))
        dismiss()
    }

    @ViewBuilder
    private func teamLogo(_ team: Team, size: CGFloat) -> some View {
        AsyncImage(url: team.logoUrl.flatMap { URL(string: $0) }) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Text(team.abbreviation)
                .font(.system(size: max(8, size * 0.4), weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - Search row

private struct SearchRow: View {
    let result: SearchResult
    let league: League

    var body: some View {
        HStack(spacing: 12) {
            avatar
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: league.icon)
                        .font(.caption2)
                        .foregroundStyle(league.color)
                    Text(result.type == "team" ? "Team · \(league.shortName)" : "Player · \(league.shortName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var avatar: some View {
        if result.type == "player" {
            PlayerAvatar(
                name: result.name,
                espnId: result.id,
                league: league,
                size: 72
            )
        } else {
            AsyncImage(
                url: result.imageUrl.flatMap { URL(string: $0) }
                    ?? League.teamLogoURL(espnId: result.id, league: league)
            ) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                default:
                    placeholder(icon: "shield.fill")
                }
            }
        }
    }

    private func placeholder(icon: String) -> some View {
        Circle()
            .fill(league.color.opacity(0.15))
            .overlay {
                Image(systemName: icon)
                    .foregroundStyle(league.color.opacity(0.7))
            }
    }
}

// MARK: - Step 2: Trigger grid

private struct TriggerStep: View {
    let entity: SearchResult
    let league: League
    let isCreating: Bool
    let onBack: () -> Void
    let onPick: (TriggerType) -> Void

    @State private var pendingTrigger: TriggerType?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                if league.triggers.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bell.slash")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("No triggers available for \(league.shortName) yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Go back", action: onBack)
                            .buttonStyle(.bordered)
                            .padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                    .padding(.horizontal, 24)
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                        ],
                        spacing: 12
                    ) {
                        ForEach(league.triggers, id: \.self) { trigger in
                            TriggerChip(
                                trigger: trigger,
                                league: league,
                                isLoading: isCreating && pendingTrigger == trigger,
                                disabled: isCreating
                            ) {
                                pendingTrigger = trigger
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                onPick(trigger)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.secondary.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            avatar
                .frame(width: 46, height: 46)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(league.color.opacity(0.8), lineWidth: 2))

            VStack(alignment: .leading, spacing: 2) {
                Text(entity.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: league.icon)
                        .font(.caption2)
                    Text(league.shortName)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(league.color)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var avatar: some View {
        if entity.type == "player" {
            PlayerAvatar(
                name: entity.name,
                espnId: entity.id,
                league: league,
                size: 120
            )
        } else {
            AsyncImage(
                url: entity.imageUrl.flatMap { URL(string: $0) }
                    ?? League.teamLogoURL(espnId: entity.id, league: league)
            ) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit()
                default: placeholder(icon: "shield.fill")
                }
            }
        }
    }

    private func placeholder(icon: String) -> some View {
        Circle()
            .fill(league.color.opacity(0.15))
            .overlay {
                Image(systemName: icon)
                    .foregroundStyle(league.color.opacity(0.7))
            }
    }
}

// MARK: - Trigger chip

private struct TriggerChip: View {
    let trigger: TriggerType
    let league: League
    let isLoading: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if isLoading {
                    ProgressView()
                        .frame(height: 32)
                } else {
                    Text(trigger.shortLabel)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(league.color)
                        .frame(height: 32)
                }
                Text(trigger.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(league.color.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(league.color.opacity(0.3), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled && !isLoading ? 0.6 : 1.0)
    }
}
