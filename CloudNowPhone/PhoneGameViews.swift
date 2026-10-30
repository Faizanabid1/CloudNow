import SwiftUI

/// What tapping or long-pressing a game card can do; supplied by the tab view.
struct PhoneGameActions {
    let showDetail: (GameInfo) -> Void
    let play: (GameInfo) -> Void
}

// MARK: - Library & Store

struct PhoneLibraryView: View {
    @Environment(GamesViewModel.self) private var viewModel
    @Environment(AuthManager.self) private var authManager
    let actions: PhoneGameActions

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            PhoneGameGrid(
                games: viewModel.filteredLibraryGames,
                isLoading: viewModel.isLibraryLoading,
                emptyText: viewModel.libraryError ?? "No games in your library yet.",
                searchText: $viewModel.librarySearchText,
                actions: actions
            )
            .navigationTitle(L10n.text("library"))
            .refreshable { await viewModel.refreshLibrary(authManager: authManager) }
        }
    }
}

struct PhoneStoreView: View {
    @Environment(GamesViewModel.self) private var viewModel
    let actions: PhoneGameActions

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            PhoneGameGrid(
                games: viewModel.filteredStoreGames,
                isLoading: viewModel.isLoading,
                emptyText: viewModel.error ?? "No games found.",
                searchText: $viewModel.storeSearchText,
                actions: actions
            )
            .navigationTitle(L10n.text("store"))
        }
    }
}

// MARK: - Building blocks

/// A titled horizontal row. Hidden when empty, unless `emptyText` explains how to fill it.
struct PhoneGameRow: View {
    let title: String
    let games: [GameInfo]
    let actions: PhoneGameActions
    var emptyText: String?

    var body: some View {
        if !games.isEmpty || emptyText != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title3.bold())
                    .padding(.horizontal)
                if games.isEmpty, let emptyText {
                    Text(emptyText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(games) { game in
                                PhoneGameCard(game: game, actions: actions)
                                    .frame(width: 104)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
    }
}

struct PhoneGameGrid: View {
    let games: [GameInfo]
    let isLoading: Bool
    let emptyText: String
    @Binding var searchText: String
    let actions: PhoneGameActions

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 130), spacing: 12)]

    var body: some View {
        ScrollView {
            PhoneSearchField(text: $searchText)
                .padding(.horizontal)
                .padding(.top, 8)

            if games.isEmpty {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    PhoneMessage(systemImage: "gamecontroller", text: emptyText)
                }
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(games) { game in
                        PhoneGameCard(game: game, actions: actions)
                    }
                }
                .padding()
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }
}

/// Inline search field. SwiftUI's `.searchable` inside a TabView re-focused itself after its
/// close button was tapped, so the keyboard kept coming back; this one only takes focus when
/// tapped.
struct PhoneSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L10n.text("search_games"), text: $text)
                    .focused($isFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { isFocused = false }
                if !text.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") { text = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.white.opacity(0.1), in: Capsule())

            if isFocused {
                Button(L10n.text("cancel")) {
                    text = ""
                    isFocused = false
                }
            }
        }
        .animation(.default, value: isFocused)
    }
}

/// Tap opens the game's page; long-press offers Play, Favorite and Details.
struct PhoneGameCard: View {
    @Environment(GamesViewModel.self) private var viewModel
    let game: GameInfo
    let actions: PhoneGameActions

    var body: some View {
        Button {
            actions.showDetail(game)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                GameBoxArt(url: game.boxArtUrl)
                    .overlay(alignment: .topTrailing) {
                        if viewModel.isFavorite(game.id) {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                                .foregroundStyle(.pink)
                                .padding(5)
                                .background(.black.opacity(0.5), in: Circle())
                                .padding(4)
                        }
                    }
                Text(game.title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Play", systemImage: "play.fill") { actions.play(game) }
            let isFavorite = viewModel.isFavorite(game.id)
            Button(
                isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: isFavorite ? "heart.slash" : "heart"
            ) {
                viewModel.toggleFavorite(game.id)
            }
            Button("Details", systemImage: "info.circle") { actions.showDetail(game) }
        }
    }
}

struct PhoneMessage: View {
    let systemImage: String
    let text: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let retry {
                Button(L10n.text("try_again"), action: retry)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }
}

// MARK: - Detail

struct PhoneGameDetailView: View {
    @Environment(GamesViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    let game: GameInfo
    let onPlay: (GameInfo) -> Void

    private var displayedGame: GameInfo {
        viewModel.gameWithPreferredStore(game)
    }

    var body: some View {
        let game = displayedGame
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SharedArtworkImage(
                        urlString: game.heroBannerUrl ?? game.heroImageUrl ?? game.screenshots.first,
                        maxPixelSize: ArtworkImagePipeline.heroArtPixelSize
                    )
                    .frame(height: 170)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    HStack(alignment: .top, spacing: 16) {
                        GameBoxArt(url: game.boxArtUrl)
                            .frame(width: 96)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(game.title)
                                .font(.title2.bold())
                            if let credits = credits(for: game) {
                                Text(credits)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if !game.genreItems.isEmpty {
                                Text(game.genreItems.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            actions(for: game)
                                .padding(.top, 6)
                        }
                    }

                    if game.variants.count > 1 {
                        storePicker(for: game)
                    }

                    if let description = game.longDescription, !description.isEmpty {
                        Text(description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("cancel"), systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    private func actions(for game: GameInfo) -> some View {
        HStack(spacing: 10) {
            Button {
                onPlay(game)
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.headline)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            let isFavorite = viewModel.isFavorite(game.id)
            Button(isFavorite ? "Remove Favorite" : "Add Favorite",
                   systemImage: isFavorite ? "heart.fill" : "heart")
            {
                viewModel.toggleFavorite(game.id)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .tint(isFavorite ? .pink : .gray)
        }
    }

    private func storePicker(for game: GameInfo) -> some View {
        Picker("Store", selection: Binding(
            get: { game.variants.first?.id ?? "" },
            set: { viewModel.setPreferredStore(gameId: game.id, variantId: $0) }
        )) {
            ForEach(game.variants, id: \.id) { variant in
                Text(variant.appStore.capitalized + (variant.isOwned ? " ✓" : ""))
                    .tag(variant.id)
            }
        }
        .pickerStyle(.segmented)
    }

    private func credits(for game: GameInfo) -> String? {
        let names = [game.developer, game.publisher].compactMap { $0 }.filter { !$0.isEmpty }
        return names.isEmpty ? nil : Array(NSOrderedSet(array: names)).compactMap { $0 as? String }.joined(separator: " · ")
    }
}
