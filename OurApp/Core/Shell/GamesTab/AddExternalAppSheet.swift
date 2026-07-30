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

    /// Starter suggestions (owners' list — Identity V first). Names only:
    /// schemes get pinned down with Test launch on a real phone.
    private static let suggestions = ["Identity V", "第五人格"]

    var body: some View {
        NavigationStack {
            Form {
                if existing == nil {
                    Section("Suggested") {
                        ForEach(Self.suggestions, id: \.self) { suggestion in
                            Button {
                                Haptics.tap()
                                name = suggestion
                            } label: {
                                Text(verbatim: suggestion)   // game titles are data
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
