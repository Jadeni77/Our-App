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
    @State private var pickName = ""
    @State private var isSearching = false
    @State private var isProbing = false
    @State private var schemeSetByProbe = false

    var body: some View {
        NavigationStack {
            Form {
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
                        .onChange(of: scheme) {
                            // A hand-edited link invalidates the last probe
                            // result; a probe-written one IS the result.
                            if schemeSetByProbe {
                                schemeSetByProbe = false
                            } else {
                                probeOpened = nil
                            }
                        }

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

                    if !SchemeCatalog.candidates(from: trimmedName).isEmpty {
                        Button {
                            Haptics.tap()
                            probeCandidates()
                        } label: {
                            HStack {
                                Text("Find launch link")
                                Spacer()
                                if isProbing { ProgressView() }
                            }
                        }
                        .disabled(isProbing)
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
                                        // Tiles read like the home screen, not
                                        // the store: catalog names win, and the
                                        // confirm field stays editable.
                                        pickName = store.verifiedDisplayName(
                                            for: result.trackName) ?? result.trackName
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
            TextField("Name", text: $pickName)
            Button("Add") { addPicked(pick) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Add this game?")
        }
    }

    /// Walks the likely schemes for the typed name. A failed attempt is
    /// silent and instant; the first success visibly opens the game — which
    /// IS the confirmation — and lands in the link field, tested.
    private func probeCandidates() {
        guard !isProbing else { return }
        isProbing = true
        probeOpened = nil
        Task {
            for candidate in SchemeCatalog.candidates(from: trimmedName) {
                guard let url = URL(string: candidate) else { continue }
                if await UIApplication.shared.open(url) {
                    schemeSetByProbe = true
                    scheme = candidate
                    probeOpened = true
                    Haptics.success()
                    isProbing = false
                    return
                }
            }
            probeOpened = false
            isProbing = false
        }
    }

    /// A picked store entry commits with its exact title and artwork; the
    /// launch link comes from the verified catalog when it knows the game,
    /// else the strongest candidate guess (the self-healing launch walks
    /// the rest — a wrong guess still falls back to the store page).
    private func addPicked(_ pick: ITunesSearch.Result) {
        guard !isAdding else { return }
        let trimmedPick = pickName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedPick.isEmpty ? pick.trackName : trimmedPick
        // An edited name can collide with an existing tile — drop back into
        // the form (the "Already added" hint takes over) instead of committing.
        guard !Self.isDuplicateName(finalName, among: store.layout.externalApps,
                                    excluding: nil) else {
            name = finalName
            return
        }
        var app = GamesLayout.ExternalApp(
            id: UUID(), name: finalName, emoji: "🎮",
            artworkURL: pick.artworkUrl512, launchURL: nil,
            storeURL: pick.trackViewUrl)
        let guess = store.verifiedScheme(for: pick.trackName)
            ?? SchemeCatalog.candidates(from: finalName).first
            ?? SchemeCatalog.candidates(from: pick.trackName).first
        app.launchURL = guess.flatMap { Self.normalizedLaunchURL(from: $0) }
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

        // A link that Test launch (or the probe) just proved is knowledge —
        // the catalog learns it with the name the owners chose.
        if probeOpened == true, let scheme = app.launchURL?.absoluteString {
            store.learnScheme(name: app.name, scheme: scheme)
        }

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
