import SwiftUI

/// One hub tile: the springboard's icon square with a label beneath, so Home
/// and the Apps tab read as one family. Coming-soon entries dim and wear a
/// small lock.
struct HubEntryTile: View {
    let entry: HubEntry

    var body: some View {
        VStack(spacing: 6) {
            TileSquare {
                Text(entry.emoji)
                    .font(.system(size: 28))
            }
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
