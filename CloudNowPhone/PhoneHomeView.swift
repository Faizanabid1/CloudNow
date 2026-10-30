import SwiftUI

/// Phone Home: a Jump Back In banner, then personal rows (Running Now, Recently Played,
/// Favorites) and discovery rows drawn from the catalog games you don't own yet.
struct PhoneHomeView: View {
    private enum Hero {
        case resume(ResumableSession)
        case running(GameInfo)
        case recent(GameInfo)
    }

    @Environment(GamesViewModel.self) private var viewModel
    @Environment(AuthManager.self) private var authManager
    @Environment(CloudSessionCoordinator.self) private var cloudSessionCoordinator
    let actions: PhoneGameActions
    let onResume: (ResumableSession) -> Void

    @State private var sessionToEnd: ActiveSessionInfo?
    @State private var endingSessionID: String?
    @State private var failedSessionID: String?

    private static let freeToPlayGenre = "FREE_TO_PLAY"
    private static let discoverRowLength = 20

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if let error = viewModel.error, viewModel.mainGames.isEmpty {
                        PhoneMessage(systemImage: "wifi.exclamationmark", text: error) {
                            Task { await viewModel.load(authManager: authManager) }
                        }
                    } else if viewModel.isLoading, viewModel.mainGames.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 240)
                    } else {
                        if let hero {
                            heroBanner(hero)
                        }
                        runningNowRow
                        PhoneGameRow(title: L10n.text("recently_played"), games: viewModel.recentlyPlayedGames, actions: actions)
                        PhoneGameRow(
                            title: L10n.text("favorites"),
                            games: viewModel.favoriteGames,
                            actions: actions,
                            emptyText: "Long-press any game, or tap ♥ on its page, to add it here."
                        )
                        PhoneGameRow(title: "Free to Play", games: freeToPlayGames, actions: actions)
                        if let genre = topGenre {
                            PhoneGameRow(
                                title: "More \(GameInfo.genreLabel(genre))",
                                games: discoverGames { $0.genreCodes.contains(genre) },
                                actions: actions
                            )
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(L10n.text("home"))
            .refreshable {
                await viewModel.refreshLibrary(authManager: authManager)
                await viewModel.refreshActiveSessions(authManager: authManager)
            }
            .confirmationDialog(
                L10n.text("end_session_title"),
                isPresented: Binding(get: { sessionToEnd != nil }, set: { if !$0 { sessionToEnd = nil } }),
                presenting: sessionToEnd
            ) { session in
                Button(L10n.text("end_session"), role: .destructive) { endSession(session) }
                Button(L10n.text("cancel"), role: .cancel) {}
            } message: { _ in
                Text(L10n.text("end_session_from_home_message"))
            }
        }
    }

    // MARK: Jump Back In

    /// A session you just left beats one still running on the server, which beats the last
    /// game you played or favorited.
    private var hero: Hero? {
        if let resumable = viewModel.resumableSession {
            return .resume(resumable)
        }
        if let running = viewModel.continuePlaying.first {
            return .running(running)
        }
        if let recent = viewModel.recentlyPlayedGames.first ?? viewModel.favoriteGames.first {
            return .recent(recent)
        }
        return nil
    }

    private func heroBanner(_ hero: Hero) -> some View {
        let game: GameInfo
        let caption: String
        let buttonTitle: String
        switch hero {
        case let .resume(resumable):
            (game, caption, buttonTitle) = (resumable.game, "Resume where you left off", "Resume")
        case let .running(running):
            (game, caption, buttonTitle) = (running, L10n.text("session_active"), "Resume")
        case let .recent(recent):
            (game, caption, buttonTitle) = (recent, "Jump back in", "Play")
        }

        return ZStack(alignment: .bottomLeading) {
            SharedArtworkImage(
                urlString: game.heroBannerUrl ?? game.heroImageUrl ?? game.screenshots.first,
                maxPixelSize: ArtworkImagePipeline.heroArtPixelSize
            )
            .frame(height: 210)
            .frame(maxWidth: .infinity)
            .clipped()
            .onTapGesture { actions.showDetail(game) }

            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(caption)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                    Text(game.title)
                        .font(.title2.bold())
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    if case let .resume(resumable) = hero {
                        onResume(resumable)
                    } else {
                        actions.play(game)
                    }
                } label: {
                    Label(buttonTitle, systemImage: "play.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding()
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal)
    }

    // MARK: Running Now

    @ViewBuilder
    private var runningNowRow: some View {
        let running = viewModel.continuePlaying
        if !running.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Running Now")
                    .font(.title3.bold())
                    .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(running) { game in
                            VStack(spacing: 6) {
                                PhoneGameCard(game: game, actions: actions)
                                if let session = activeSession(for: game) {
                                    endButton(for: session)
                                }
                            }
                            .frame(width: 104)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func endButton(for session: ActiveSessionInfo) -> some View {
        Button(role: .destructive) {
            sessionToEnd = session
        } label: {
            if endingSessionID == session.sessionId {
                ProgressView()
            } else {
                Text(failedSessionID == session.sessionId ? L10n.text("retry") : L10n.text("end_session"))
                    .font(.caption.weight(.semibold))
            }
        }
        .buttonStyle(.bordered)
        .disabled(!canEndSession(session.sessionId))
    }

    private func activeSession(for game: GameInfo) -> ActiveSessionInfo? {
        viewModel.activeSessions.first { session in
            game.variants.contains { variant in
                guard let appId = variant.appId, let sessionAppId = session.appId else { return false }
                return appId == sessionAppId
            }
        }
    }

    /// Mirrors HomeView: a session this app holds a lease on is ended through that lease; any
    /// other server session is ended directly, but not while a different lease is held.
    private func canEndSession(_ sessionID: String) -> Bool {
        guard endingSessionID == nil, !cloudSessionCoordinator.isEndingServerSession else { return false }
        guard let lease = cloudSessionCoordinator.serverSession else { return true }
        return lease.provider == .geForceNow && lease.serverSessionID == sessionID
    }

    private func endSession(_ session: ActiveSessionInfo) {
        guard let account = authManager.session, canEndSession(session.sessionId) else { return }
        endingSessionID = session.sessionId
        failedSessionID = nil
        Task { @MainActor in
            defer { endingSessionID = nil }
            let didEnd: Bool
            if let lease = cloudSessionCoordinator.serverSession,
               lease.provider == .geForceNow,
               lease.serverSessionID == session.sessionId
            {
                didEnd = await cloudSessionCoordinator.endServerSessionUsingProvider(lease)
            } else {
                didEnd = await viewModel.endActiveSession(
                    session,
                    authManager: authManager,
                    coordinator: cloudSessionCoordinator
                )
            }
            // The account may have changed while the request was in flight.
            guard let currentAccount = authManager.session,
                  currentAccount.provider.idpId == account.provider.idpId,
                  currentAccount.user.userId == account.user.userId
            else { return }
            guard didEnd else {
                failedSessionID = session.sessionId
                return
            }
            viewModel.markSessionStopped(
                session.sessionId,
                idpId: account.provider.idpId,
                userId: account.user.userId
            )
            await viewModel.refreshActiveSessions(authManager: authManager)
        }
    }

    // MARK: Discover

    private var freeToPlayGames: [GameInfo] {
        discoverGames { $0.genreCodes.contains(Self.freeToPlayGenre) }
    }

    /// The genre you play and favorite most, falling back to your library's.
    private var topGenre: String? {
        let personal = viewModel.recentlyPlayedGames + viewModel.favoriteGames
        let pool = personal.isEmpty ? viewModel.libraryGames : personal
        var counts: [String: Int] = [:]
        for game in pool {
            for genre in game.genreCodes where genre != Self.freeToPlayGenre {
                counts[genre, default: 0] += 1
            }
        }
        // Ties break alphabetically so the row doesn't flip between renders.
        return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }

    /// Catalog games you don't own yet, once each.
    private func discoverGames(where matches: (GameInfo) -> Bool) -> [GameInfo] {
        var seen = Set<String>()
        var games: [GameInfo] = []
        for game in viewModel.mainGames where !game.isInLibrary && matches(game) && seen.insert(game.id).inserted {
            games.append(game)
            if games.count == Self.discoverRowLength { break }
        }
        return games
    }
}
