import SwiftUI

/// Add (or edit) an external app tile (S7): a tiny suggestion list, manual
/// name + URL-scheme entry, and a Test-launch probe — how we pin down
/// undocumented schemes on a real phone. Artwork / store-link enrichment
/// happens after commit, outside this sheet.
struct AddExternalAppSheet: View {
    var existing: GamesLayout.ExternalApp?
    let onCommit: (GamesLayout.ExternalApp) -> Void

    @Environment(GamesLayoutStore.self) private var store
    @Environment(ArtworkStore.self) private var artwork
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var scheme = ""
    @State private var probeOpened: Bool?
    @State private var isAdding = false
    @State private var searchResults: [ITunesSearch.Result] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var pendingPick: ITunesSearch.Result?
    @State private var isSearching = false

    /// Starter suggestions (owners' list — Identity V first). An entry
    /// carries its scheme once one is verified with Test launch on a real
    /// phone; until then, tapping a suggestion derives a testable guess
    /// from the name.
    private struct Suggestion {
        let name: String
        /// Verified on-device — nil means "derive a guess to test".
        var scheme: String?
    }

    private static let suggestions: [Suggestion] = [
        .init(name: "Identity V"),
        .init(name: "第五人格"),
        .init(name: "Wild Rift", scheme: "wildrift://"),           // verified 2026-07-30
        .init(name: "Clash of Clans", scheme: "clashofclans://"),  // verified 2026-07-30
    ]

    /// Best-effort scheme guess: the latin letters and digits of the name,
    /// lowercased, plus `://` — a starting point for Test launch, not a
    /// promise. Fully non-latin names get an empty field instead of junk.
    static func derivedScheme(from name: String) -> String {
        let ascii = name.lowercased().unicodeScalars.filter {
            $0.isASCII && CharacterSet.alphanumerics.contains($0)
        }
        guard !ascii.isEmpty else { return "" }
        return String(String.UnicodeScalarView(ascii)) + "://"
    }

    var body: some View {
        NavigationStack {
            Form {
                if existing == nil {
                    Section("Suggested") {
                        ForEach(Self.suggestions, id: \.name) { suggestion in
                            Button {
                                Haptics.tap()
                                name = suggestion.name
                                scheme = suggestion.scheme
                                    ?? Self.derivedScheme(from: suggestion.name)
                                probeOpened = nil
                            } label: {
                                Text(verbatim: suggestion.name)   // game titles are data
                            }
                        }
                    }
                }

                Section {
                    TextField("Name", text: $name)
                    if isDuplicate {
                        Text("Already added")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    TextField("URL scheme (optional)", text: $scheme)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onChange(of: scheme) { probeOpened = nil }

                    if let url = normalizedSchemeURL {
                        Button {
                            Haptics.tap()
                            UIApplication.shared.open(url, options: [:]) { opened in
                                probeOpened = opened
                                if opened { Haptics.success() }
                            }
                        } label: {
                            HStack {
                                Text("Test launch")
                                Spacer()
                                if let probeOpened {
                                    // Two literal branches keep both keys
                                    // visible to catalog extraction.
                                    (probeOpened ? Text("Opened") : Text("Couldn't open"))
                                        .foregroundStyle(probeOpened ? .green : .secondary)
                                }
                            }
                        }
                    }
                } footer: {
                    // Most people can't know an app's scheme — explain why it
                    // matters and that skipping it still gives a working tile
                    // (the store page shows Open for installed apps).
                    Text("iOS needs an app's link (URL scheme) to open it directly. Without one, the tile opens its App Store page instead.")
                }

                // The lookup the owners asked for (2026-07-30): as the name is
                // typed, matching store entries appear — tap one, confirm, and
                // the tile arrives with the exact title and artwork.
                if existing == nil, !searchResults.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(searchResults, id: \.self) { result in
                                    Button {
                                        Haptics.tap()
                                        pendingPick = result
                                    } label: {
                                        VStack(spacing: 4) {
                                            AsyncImage(url: result.artworkUrl100) { image in
                                                image.resizable().scaledToFill()
                                            } placeholder: {
                                                Color.secondary.opacity(0.15)
                                            }
                                            .frame(width: 48, height: 48)
                                            .clipShape(RoundedRectangle(cornerRadius: 10,
                                                                        style: .continuous))
                                            Text(verbatim: result.trackName)
                                                .font(.caption2)
                                                .lineLimit(1)
                                                .frame(width: 64)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle(existing.map { Text(verbatim: $0.name) } ?? Text("Add a game"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Haptics.tap()
                        commit()
                    } label: {
                        if isAdding {
                            ProgressView()
                        } else {
                            existing == nil ? Text("Add") : Text("Done")
                        }
                    }
                    // While matches are on screen (or being fetched), the
                    // picker is the only add path — a bare Add here would
                    // commit a half-typed search as a tile (owners' report,
                    // 2026-07-30). Manual Add returns when nothing matches.
                    .disabled(trimmedName.isEmpty || isDuplicate || isAdding
                        || (existing == nil && (isSearching || !searchResults.isEmpty)))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isAdding)
                }
            }
        }
        .onAppear {
            guard let existing else { return }
            name = existing.name
            scheme = existing.launchURL?.absoluteString ?? ""
        }
        .onChange(of: name) {
            searchTask?.cancel()
            let query = trimmedName
            guard existing == nil, query.count >= 2 else {
                searchResults = []
                isSearching = false
                return
            }
            isSearching = true
            searchTask = Task {
                // Debounce keystrokes; a newer query cancels this one (and
                // owns the isSearching flag from then on).
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                let found = await ITunesSearch.search(name: query)
                guard !Task.isCancelled else { return }
                searchResults = found.filter {
                    !Self.isDuplicateName($0.trackName,
                                          among: store.layout.externalApps,
                                          excluding: nil)
                }
                isSearching = false
            }
        }
        .alert(
            Text(verbatim: pendingPick?.trackName ?? ""),
            isPresented: Binding(
                get: { pendingPick != nil },
                set: { if !$0 { pendingPick = nil } }),
            presenting: pendingPick
        ) { pick in
            Button("Add") { addPicked(pick) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Add this game?")
        }
    }

    /// A picked store entry commits with its exact title and artwork; the
    /// launch link starts as a derived guess (Test launch refines it later
    /// via Edit — a wrong guess still falls back to the store page).
    private func addPicked(_ pick: ITunesSearch.Result) {
        guard !isAdding else { return }
        var app = GamesLayout.ExternalApp(
            id: UUID(), name: pick.trackName, emoji: "🎮",
            artworkURL: pick.artworkUrl512, launchURL: nil,
            storeURL: pick.trackViewUrl)
        app.launchURL = Self.normalizedLaunchURL(
            from: Self.derivedScheme(from: pick.trackName))
        isAdding = true
        Task {
            if let artworkURL = pick.artworkUrl512 {
                await artwork.refreshArtwork(from: artworkURL, for: app.id)
            }
            onCommit(app)
            dismiss()
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One tile per game: the same name (trimmed, case-insensitive) can't be
    /// added twice — though an edit may keep its own.
    private var isDuplicate: Bool {
        Self.isDuplicateName(trimmedName, among: store.layout.externalApps,
                             excluding: existing?.id)
    }

    static func isDuplicateName(_ name: String,
                                among externalApps: [GamesLayout.ExternalApp],
                                excluding excludedID: UUID?) -> Bool {
        let candidate = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !candidate.isEmpty else { return false }
        return externalApps.contains {
            $0.id != excludedID
                && $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == candidate
        }
    }

    private var normalizedSchemeURL: URL? {
        Self.normalizedLaunchURL(from: scheme)
    }

    /// A bare app name is a valid scheme seed — "identityv" becomes
    /// "identityv://" — and links whose query carries spaces (a Shortcuts
    /// run-shortcut name, say) get percent-encoded rather than rejected.
    static func normalizedLaunchURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : trimmed + "://"
        if let url = URL(string: candidate) { return url }
        guard let encoded = candidate.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: encoded)
    }

    private func commit() {
        guard !isAdding else { return }
        var app = existing ?? GamesLayout.ExternalApp(
            id: UUID(), name: "", emoji: "🎮",
            artworkURL: nil, launchURL: nil, storeURL: nil)
        app.name = trimmedName        // user data — stored verbatim (S6)
        app.launchURL = normalizedSchemeURL

        // Edits commit instantly (the tile already exists on screen).
        guard existing == nil else {
            onCommit(app)
            dismiss()
            return
        }

        // New tiles get dressed BEFORE they're born — fetch artwork and the
        // store link first (network calls carry timeouts, and every failure
        // still lands on the emoji fallback), so the grid never flashes 🎮
        // and then swaps.
        isAdding = true
        Task {
            // Dress only on a plausible title match — fuzzy search must
            // never put a stranger's icon on a manually named tile.
            if let found = await ITunesSearch.lookup(name: app.name),
               ITunesSearch.plausibleMatch(typed: app.name,
                                           trackName: found.trackName) {
                app.artworkURL = found.artworkUrl512 ?? app.artworkURL
                app.storeURL = found.trackViewUrl ?? app.storeURL
                if let artworkURL = found.artworkUrl512 {
                    await artwork.refreshArtwork(from: artworkURL, for: app.id)
                }
            }
            onCommit(app)
            dismiss()
        }
    }
}

#Preview {
    AddExternalAppSheet(onCommit: { _ in })
        .environment(GamesLayoutStore(
            modules: [],
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("preview-add-sheet.json")))
}
