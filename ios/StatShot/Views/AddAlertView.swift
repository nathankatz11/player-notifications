import SwiftUI

/// Context for the game-scoped picker mode — shown when the user taps
/// "Follow a Player from This Game" inside `GameDetailSheet`. Scopes the
/// picker to the two teams in that game and their rosters, instead of a
/// free-text search.
struct GameContext: Equatable {
    struct Side: Equatable {
        let teamId: String
        let teamName: String
        let teamAbbr: String
    }
    let league: League
    let away: Side
    let home: Side
}

/// Two-decision alert creation:
///   1. Who — unified player + team search (league inferred from the active filter).
///   2. What — tap a big trigger chip → creates the alert and dismisses.
///
/// When initialized with a `GameContext`, the first step is a roster picker
/// for just the two teams in the game (no free-text search).
///
/// Delivery method defaults to `.push`; users change it later from AlertDetailView.
struct AddAlertView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = SubscriptionViewModel()

    private let initialLeague: League?
    private let gameContext: GameContext?

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
    @State private var liveGames: [LiveGame] = []
    @State private var pickedGameForFollow: LiveGame?

    // Roster-mode state (only used when gameContext != nil)
    @State private var selectedSide: RosterSide = .away
    @State private var awayRoster: [RosterPlayer] = []
    @State private var homeRoster: [RosterPlayer] = []
    @State private var rosterLoading = false

    private enum RosterSide { case away, home }

    init(initialLeague: League? = nil) {
        self.initialLeague = initialLeague
        self.gameContext = nil
        if let league = initialLeague {
            _selectedLeague = State(initialValue: league)
        }
    }

    init(gameContext: GameContext) {
        self.initialLeague = gameContext.league
        self.gameContext = gameContext
        _selectedLeague = State(initialValue: gameContext.league)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .search:
                    if gameContext != nil {
                        rosterStep
                    } else {
                        searchStep
                    }
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
                if gameContext != nil {
                    await loadRosters()
                } else {
                    await reloadForLeague()
                }
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
            group.addTask {
                do {
                    let data = try await APIService.shared.fetchScores(
                        league: self.selectedLeague.rawValue
                    )
                    let decoded = try JSONDecoder().decode(
                        ScoresResponse.self,
                        from: data
                    )
                    await MainActor.run { self.liveGames = decoded.games }
                } catch {
                    await MainActor.run { self.liveGames = [] }
                }
            }
        }
    }

    // MARK: - Step 1 (game-scoped): Roster picker

    private var rosterStep: some View {
        VStack(spacing: 0) {
            if let ctx = gameContext {
                sidePicker(ctx: ctx)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 10)

                Divider()

                ScrollView {
                    let side = selectedSide == .away ? ctx.away : ctx.home
                    let roster = selectedSide == .away ? awayRoster : homeRoster
                    LazyVStack(spacing: 8) {
                        teamFollowRow(side: side, league: ctx.league)
                        if rosterLoading && roster.isEmpty {
                            ProgressView()
                                .padding(.top, 24)
                        } else if roster.isEmpty {
                            Text("No roster available.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 24)
                        } else {
                            ForEach(roster) { player in
                                rosterRow(player: player, league: ctx.league)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private func sidePicker(ctx: GameContext) -> some View {
        HStack(spacing: 8) {
            sideButton(ctx.away, side: .away, league: ctx.league)
            sideButton(ctx.home, side: .home, league: ctx.league)
        }
    }

    private func sideButton(_ side: GameContext.Side, side selected: RosterSide, league: League) -> some View {
        let isOn = selectedSide == selected
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selectedSide = selected
        } label: {
            HStack(spacing: 8) {
                AsyncImage(
                    url: League.teamLogoURL(espnId: side.teamId, league: league)
                ) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Circle().fill(league.color.opacity(0.2))
                }
                .frame(width: 22, height: 22)
                Text(side.teamAbbr)
                    .font(.subheadline.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                isOn ? league.color.opacity(0.25) : Color.secondary.opacity(0.10),
                in: Capsule()
            )
            .overlay(
                isOn ? Capsule().strokeBorder(league.color, lineWidth: 1.5) : nil
            )
        }
        .buttonStyle(.plain)
    }

    private func teamFollowRow(side: GameContext.Side, league: League) -> some View {
        Button {
            let team = SearchResult(
                id: side.teamId,
                name: side.teamName,
                type: "team",
                imageUrl: nil,
                position: nil
            )
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            step = .trigger(team, league)
        } label: {
            HStack(spacing: 12) {
                AsyncImage(
                    url: League.teamLogoURL(espnId: side.teamId, league: league)
                ) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Circle().fill(league.color.opacity(0.2))
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Follow \(side.teamName)")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Team alerts (wins, losses…)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func rosterRow(player: RosterPlayer, league: League) -> some View {
        Button {
            let entity = SearchResult(
                id: player.id,
                name: player.name,
                type: "player",
                imageUrl: player.headshotUrl,
                position: player.position
            )
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            step = .trigger(entity, league)
        } label: {
            HStack(spacing: 12) {
                PlayerAvatar(
                    name: player.name,
                    espnId: player.id,
                    league: league,
                    storedURL: player.headshotUrl,
                    size: 72
                )
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    if let pos = player.position, !pos.isEmpty {
                        Text(pos)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func loadRosters() async {
        guard let ctx = gameContext else { return }
        rosterLoading = true
        defer { rosterLoading = false }

        async let away = APIService.shared.fetchRoster(
            league: ctx.league.rawValue,
            teamId: ctx.away.teamId
        )
        async let home = APIService.shared.fetchRoster(
            league: ctx.league.rawValue,
            teamId: ctx.home.teamId
        )
        do {
            awayRoster = try await away
        } catch {
            awayRoster = []
        }
        do {
            homeRoster = try await home
        } catch {
            homeRoster = []
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
        .confirmationDialog(
            "Follow a team",
            isPresented: .init(
                get: { pickedGameForFollow != nil },
                set: { if !$0 { pickedGameForFollow = nil } }
            ),
            presenting: pickedGameForFollow
        ) { game in
            if let away = game.awayTeam {
                Button(away.team) {
                    pickTeamFromCompetitor(away)
                }
            }
            if let home = game.homeTeam {
                Button(home.team) {
                    pickTeamFromCompetitor(home)
                }
            }
        }
    }

    private func pickTeamFromCompetitor(_ comp: Competitor) {
        let result = SearchResult(
            id: comp.teamId ?? comp.abbreviation,
            name: comp.team,
            type: "team",
            imageUrl: nil,
            position: nil
        )
        pickEntity(result)
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

    // MARK: - Discovery (empty query)

    @ViewBuilder
    private var quickPicks: some View {
        // 1. Live / today's games — tap opens the game-scoped roster picker
        let activeGames = liveGames.filter { $0.status == "in" || $0.status == "pre" }
        if !activeGames.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Today's Games")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(activeGames) { game in
                            discoveryScoreTile(game)
                        }
                    }
                }
            }
        }

        // 2. All teams — visual logo grid
        if !viewModel.teams.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Teams")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 72), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(viewModel.teams) { team in
                        Button {
                            pickTeam(team)
                        } label: {
                            VStack(spacing: 6) {
                                teamLogo(team, size: 48)
                                Text(team.abbreviation)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                            .frame(width: 72)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        // 3. Trending players
        if !viewModel.trendingPlayers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Trending Players")
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

        if viewModel.isLoadingTeams && viewModel.teams.isEmpty {
            HStack { Spacer(); ProgressView(); Spacer() }
        }
    }

    /// Compact score tile for the discovery section. Tapping shows a quick
    /// picker for which team to follow.
    private func discoveryScoreTile(_ game: LiveGame) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            pickedGameForFollow = game
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                tileTeamRow(game.awayTeam)
                tileTeamRow(game.homeTeam)
                Text(game.statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(game.isLive ? .red : .secondary)
            }
            .padding(10)
            .frame(width: 160)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func tileTeamRow(_ side: Competitor?) -> some View {
        HStack(spacing: 6) {
            AsyncImage(
                url: tileLogoURL(side?.abbreviation ?? "")
            ) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Circle().fill(.tertiary)
            }
            .frame(width: 18, height: 18)
            Text(side?.abbreviation ?? "—")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Spacer()
            Text(side?.score ?? "—")
                .font(.subheadline.bold())
                .monospacedDigit()
        }
    }

    private func tileLogoURL(_ abbr: String) -> URL? {
        URL(string: "https://a.espncdn.com/i/teamlogos/\(selectedLeague.espnSport)/500/\(abbr.lowercased()).png")
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
            imageUrl: nil,
            position: nil
        )
        pickEntity(result)
    }

    private func pickTeam(_ team: Team) {
        let result = SearchResult(
            id: team.id,
            name: team.name,
            type: "team",
            imageUrl: team.logoUrl,
            position: nil
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
                } else if shouldGroupPlayerTriggers {
                    groupedTriggers
                        .padding(16)
                } else {
                    LazyVGrid(
                        columns: triggerColumns,
                        spacing: 12
                    ) {
                        ForEach(league.triggers, id: \.self) { trigger in
                            triggerChip(for: trigger)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    /// Show grouped sections only when the selected league supplies role
    /// groupings for its triggers AND the entity is a player. Teams and
    /// leagues without role grouping fall back to the original flat grid.
    private var shouldGroupPlayerTriggers: Bool {
        guard entity.type == "player" else { return false }
        return league.triggers.contains { $0.roleGroup(for: league) != nil }
    }

    private var triggerColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
    }

    @ViewBuilder
    private var groupedTriggers: some View {
        // Bucket each trigger under its league-specific role group. Triggers
        // that don't belong to any group (shouldn't happen for leagues that
        // opt into grouping, but handled defensively) are dropped here; the
        // fallback grid path covers leagues without groupings entirely.
        let groups: [(RoleGroup, [TriggerType])] = {
            var buckets: [RoleGroup: [TriggerType]] = [:]
            for trigger in league.triggers {
                if let group = trigger.roleGroup(for: league) {
                    buckets[group, default: []].append(trigger)
                }
            }
            return buckets
                .map { ($0.key, $0.value) }
                .sorted { $0.0 < $1.0 }
        }()

        VStack(alignment: .leading, spacing: 18) {
            ForEach(groups, id: \.0) { group, triggers in
                triggerSection(title: group.rawValue, triggers: triggers)
            }
        }
    }

    private func triggerSection(title: String, triggers: [TriggerType]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            LazyVGrid(columns: triggerColumns, spacing: 12) {
                ForEach(triggers, id: \.self) { trigger in
                    triggerChip(for: trigger)
                }
            }
        }
    }

    private func triggerChip(for trigger: TriggerType) -> some View {
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
