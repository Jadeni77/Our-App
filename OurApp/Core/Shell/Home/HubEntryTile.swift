import SwiftUI

/// One hub tile: a drawn icon with a label beneath. The coloured squircle *is*
/// the tile — no glass square behind it, which would be two nested cards
/// saying the same thing (H11). Coming-soon entries dim and wear a small lock.
struct HubEntryTile: View {
    let entry: HubEntry

    var body: some View {
        VStack(spacing: 6) {
            HubIconView(icon: entry.icon)
                // Capped so a short row doesn't inflate the icons: three tiles
                // sharing the full width would render far larger than the
                // springboard's. The column stays wide; only the icon is capped.
                .frame(maxWidth: 78)
                .overlay(alignment: .topTrailing) {
                    if let makeBadge = entry.makeBadge {
                        makeBadge()
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !entry.isReady {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(5)
                    }
                }

            Text(entry.name)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .frame(height: 26, alignment: .top)
        }
        .opacity(entry.isReady ? 1 : 0.45)
    }
}

#Preview {
    HStack(spacing: 12) {
        ForEach(HubCatalog.entries) { HubEntryTile(entry: $0) }
    }
    .frame(width: 300)
    .padding(20)
    .background(Theme.duskGradient)
    .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
