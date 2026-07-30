import SwiftUI

/// Add (or edit) an external app tile (S7): a tiny suggestion list, manual
/// name + URL-scheme entry, and a Test-launch probe — how we pin down
/// undocumented schemes on a real phone. Artwork / store-link enrichment
/// happens after commit, outside this sheet.
struct AddExternalAppSheet: View {
    var existing: GamesLayout.ExternalApp?
    let onCommit: (GamesLayout.ExternalApp) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var scheme = ""
    @State private var probeOpened: Bool?

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
            }
            .navigationTitle(existing.map { Text(verbatim: $0.name) } ?? Text("Add a game"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Haptics.tap()
                        commit()
                    } label: {
                        existing == nil ? Text("Add") : Text("Done")
                    }
                    .disabled(trimmedName.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            guard let existing else { return }
            name = existing.name
            scheme = existing.launchURL?.absoluteString ?? ""
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A bare app name is a valid scheme seed — "identityv" becomes
    /// "identityv://" so Test launch and the tile both get a real URL.
    private var normalizedSchemeURL: URL? {
        let trimmed = scheme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed.contains("://") ? trimmed : trimmed + "://")
    }

    private func commit() {
        var app = existing ?? GamesLayout.ExternalApp(
            id: UUID(), name: "", emoji: "🎮",
            artworkURL: nil, launchURL: nil, storeURL: nil)
        app.name = trimmedName        // user data — stored verbatim (S6)
        app.launchURL = normalizedSchemeURL
        onCommit(app)
        dismiss()
    }
}

#Preview {
    AddExternalAppSheet(onCommit: { _ in })
}
