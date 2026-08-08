import SwiftUI

/// Home's hub: a glass panel of topic tiles above the tab bar. Up to four
/// tiles share the width evenly; a fifth turns the row into a horizontal
/// scroller at the same tile size. It never becomes a grid — the moment it
/// wants to be one it has become the springboard, which lives one tab over.
struct HubEntryRow: View {
    let entries: [HubEntry]

    /// The reason a dimmed tile isn't tappable yet, shown briefly on tap.
    @State private var note: LocalizedStringResource?
    @State private var noteDismissal: Task<Void, Never>?

    private var scrolls: Bool { entries.count > 4 }

    var body: some View {
        VStack(spacing: 8) {
            if let note {
                Text(note)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.indigo.opacity(0.75)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            panel
        }
        .animation(Theme.springy, value: note != nil)
    }

    @ViewBuilder private var panel: some View {
        Group {
            if scrolls {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(entries) { tile(for: $0).frame(width: 74) }
                    }
                    .padding(.horizontal, 14)
                }
            } else {
                HStack(spacing: 12) {
                    ForEach(entries) { tile(for: $0).frame(maxWidth: .infinity) }
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 26)
    }

    @ViewBuilder private func tile(for entry: HubEntry) -> some View {
        switch entry.kind {
        case .page:
            NavigationLink(value: HubRoute(entryID: entry.id)) {
                HubEntryTile(entry: entry)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
        case .comingSoon(let reason):
            Button {
                show(reason)
            } label: {
                HubEntryTile(entry: entry)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(reason))
        }
    }

    private func show(_ reason: LocalizedStringResource) {
        Haptics.tap()
        note = reason
        noteDismissal?.cancel()
        noteDismissal = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            note = nil
        }
    }
}

#Preview {
    NavigationStack {
        VStack {
            Spacer()
            HubEntryRow(entries: HubCatalog.entries)
                .padding(.horizontal, 14)
        }
        .background(Theme.duskGradient)
    }
    .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
