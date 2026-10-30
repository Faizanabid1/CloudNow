import SwiftUI

/// Phone counterpart of MainTabView: same model, data loading and stream presentation, with
/// touch-sized screens. Settings reuses the shared SettingsView form, which adapts to phones.
struct PhoneMainTabView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(CloudSessionCoordinator.self) private var cloudSessionCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: GamesViewModel
    @State private var controllerNavigation = UIControllerNavigationCoordinator()
    @State private var selectedGame: GameInfo?
    /// Set from the detail sheet; the stream opens once the sheet has finished dismissing.
    @State private var pendingPlay: GameInfo?
    @State private var gameToPlay: GameInfo?
    @State private var sessionToResume: ActiveSessionInfo?
    @State private var directSessionToResume: SessionInfo?
    @State private var metrics = PhoneMetrics.forWidth(700)
    /// Off for UI-testing fixtures, which supply their own games.
    private let loadsRemoteData: Bool

    init(viewModel: GamesViewModel = GamesViewModel(), loadsRemoteData: Bool = true) {
        _viewModel = State(initialValue: viewModel)
        self.loadsRemoteData = loadsRemoteData
    }

    var body: some View {
        TabView {
            Tab(L10n.text("home"), systemImage: "house.fill") {
                PhoneHomeView(actions: gameActions, onResume: resume)
            }
            Tab(L10n.text("library"), systemImage: "books.vertical.fill") {
                PhoneLibraryView(actions: gameActions)
            }
            Tab(L10n.text("store"), systemImage: "bag.fill") {
                PhoneStoreView(actions: gameActions)
            }
            Tab(L10n.text("settings"), systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
        // A tab bar on iPhone; a sidebar that can collapse to a top tab bar on iPad.
        .tabViewStyle(.sidebarAdaptable)
        .environment(\.phoneMetrics, metrics)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            metrics = PhoneMetrics.forWidth(width)
        }
        .environment(viewModel)
        .environment(controllerNavigation)
        .task {
            guard loadsRemoteData else { return }
            await viewModel.load(authManager: authManager)
            viewModel.restoreResumableSession(from: cloudSessionCoordinator.serverSession)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                viewModel.cancelStoreConnection()
            }
            guard phase == .active, loadsRemoteData else { return }
            viewModel.startForegroundLibraryRefresh(authManager: authManager)
        }
        .onDisappear {
            viewModel.cancelForegroundLibraryRefresh()
        }
        .onChange(of: viewModel.streamSettings) { viewModel.saveSettings() }
        .onChange(of: viewModel.availableResolutions, initial: true) {
            PhoneResolution.applyDefaultIfNeeded(to: viewModel)
        }
        .onChange(of: gameToPlay) { _, new in
            if new == nil {
                MemoryLifecycleCoordinator.shared.streamDidClose()
                directSessionToResume = nil
                Task { await viewModel.refreshActiveSessions(authManager: authManager) }
            } else {
                MemoryLifecycleCoordinator.shared.streamWillOpen()
            }
        }
        .sheet(item: $selectedGame, onDismiss: startPendingPlay) { game in
            PhoneGameDetailView(game: game) { chosen in
                pendingPlay = chosen
                selectedGame = nil
            }
            .environment(viewModel)
            // A roomy page-sized sheet on iPad; phones present full height either way.
            .presentationSizing(.page)
        }
        .fullScreenCover(item: $gameToPlay) { game in
            StreamView(
                game: game,
                settings: viewModel.streamSettings,
                existingSession: sessionToResume,
                directSession: directSessionToResume,
                onDismiss: {
                    gameToPlay = nil
                    sessionToResume = nil
                },
                onLeave: { leftGame, session in
                    viewModel.resumableSession = ResumableSession(game: leftGame, session: session, leftAt: Date())
                }
            )
            .environment(authManager)
            .environment(viewModel)
            .blocksGlobalControllerNavigation(mode: .streaming)
            .environment(controllerNavigation)
        }
    }

    private var gameActions: PhoneGameActions {
        PhoneGameActions(showDetail: { selectedGame = $0 }, play: play)
    }

    private func startPendingPlay() {
        guard let game = pendingPlay else { return }
        pendingPlay = nil
        play(game)
    }

    /// Same session matching as MainTabView: reattach to a running server session for this game.
    private func play(_ game: GameInfo) {
        directSessionToResume = nil
        sessionToResume = viewModel.activeSessions.first { session in
            game.variants.contains { variant in
                guard let appId = variant.appId, let sessionAppId = session.appId else { return false }
                return appId == sessionAppId
            }
        }
        gameToPlay = game
    }

    private func resume(_ resumable: ResumableSession) {
        directSessionToResume = resumable.session
        sessionToResume = nil
        gameToPlay = resumable.game
    }
}
