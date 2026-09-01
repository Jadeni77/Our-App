#if DEBUG
import Foundation
import SwiftData
import UIKit

/// `-seedAlbums` files a small library into four albums so `AlbumDetailView`
/// and `AlbumsGridView` have something worth judging them by: several date
/// sections, a photo filed into two albums at once, a cover deliberately
/// chosen away from the newest member, undated photos filed without a
/// memory behind them, and one album left genuinely empty.
///
/// Writes its own four memories rather than reusing `-seedMemories`'s three —
/// this needs specific days, specific counts and specific asset ids to hand
/// to `AlbumStore.add`, none of which that fixture happens to have. Safe
/// alongside `-seedMemories`: the two seeds gate on different models
/// (`Memory` there, `Album` here), so either can run with or without the
/// other and neither doubles what it wrote last time.
///
/// DEBUG only, and it declines the moment any album already exists, so a
/// real album either of you made can never be sat on top of.
enum AlbumDebugSeed {
    @MainActor
    static func runIfRequested(in container: ModelContainer,
                               identity: CoupleIdentityStore) {
        guard ProcessInfo.processInfo.arguments.contains("-seedAlbums") else { return }

        let context = ModelContext(container)
        guard (try? context.fetchCount(FetchDescriptor<Album>())) == 0 else { return }

        let store = MemoryPhotoStore()
        let calendar = Calendar(identifier: .gregorian)
        let authorID = identity.authorID

        // One memory per day, spread over months rather than clustered, so
        // both `MemoriesView`'s timeline and `AlbumDetailView`'s sections
        // have more than one heading to show. Counts vary (1, 2, 3, 5) the
        // way a real couple's days do — most days are one photo, a few days
        // are a dozen.
        let days: [(note: String, day: DateComponents, colours: [[UIColor]])] = [
            ("you, laughing at nothing",
             DateComponents(year: 2024, month: 4, day: 26),
             [[.systemPink, .systemRed]]),
            ("第一次带你走那条巷子",
             DateComponents(year: 2024, month: 5, day: 17),
             [[.systemGray, .systemIndigo], [.systemPurple]]),
            ("golden hour, forgot the groceries",
             DateComponents(year: 2024, month: 6, day: 4),
             [[.systemYellow, .systemOrange], [.systemBrown], [.systemOrange]]),
            ("finally, the coast",
             DateComponents(year: 2024, month: 6, day: 11),
             [[.systemOrange, .systemYellow], [.systemTeal, .systemCyan], [.systemPink],
              [.systemYellow], [.systemOrange, .systemPink]]),
        ]

        // Offset well clear of `-seedMemories`'s own indices so the two
        // seeds' pictures never render identical when both flags run
        // together, which they're meant to.
        var pictureIndex = 1_000
        var assetsByNote: [String: [String]] = [:]
        for entry in days {
            guard let date = calendar.date(from: entry.day) else { continue }
            var ids: [String] = []
            for colours in entry.colours {
                defer { pictureIndex += 1 }
                guard let id = try? store.save(MemoryDebugSeed.picture(index: pictureIndex,
                                                                       colours: colours))
                else { continue }
                ids.append(id)
            }
            guard !ids.isEmpty else { continue }
            assetsByNote[entry.note] = ids
            context.insert(Memory(note: entry.note, day: date, authorID: authorID, photoIDs: ids))
        }
        try? context.save()

        // The real path: `Memory.photoIDs` becomes `Photo` rows, dated from
        // whichever day named them — the same call `MemoriesView` makes on
        // every appear.
        PhotoLibrary.seed(in: context)

        // Two photos with no memory at all, so `takenAt` is nil rather than
        // merely unset-until-seeded. A memory always gives its photos a day
        // (or deliberately withholds one, per `MemoryDebugSeed`'s undated
        // memory) — the only way to get a *filed* photo with no capture date
        // is to skip the memory entirely and write the `Photo` row directly.
        var undatedIDs: [String] = []
        for colours in [[UIColor.systemMint, .systemTeal], [.systemBrown, .systemGray]] {
            defer { pictureIndex += 1 }
            guard let id = try? store.save(MemoryDebugSeed.picture(index: pictureIndex,
                                                                    colours: colours))
            else { continue }
            undatedIDs.append(id)
            context.insert(Photo(assetID: id, authorID: authorID, takenAt: nil))
        }
        try? context.save()

        guard let coast = assetsByNote["finally, the coast"],
              let groceries = assetsByNote["golden hour, forgot the groceries"],
              let alley = assetsByNote["第一次带你走那条巷子"],
              let laughing = assetsByNote["you, laughing at nothing"]
        else { return }

        // 🎀 — the favourites: two dated days plus both undated photos, so
        // its own detail view shows several date sections *and* the trailing
        // "Sometime" section on one screen.
        let ribbon = AlbumStore.create(name: "🎀", authorID: authorID, in: context)
        ribbon.caption = "the ones we keep going back to"
        for asset in [coast[0], coast[2], groceries[0]] + undatedIDs {
            AlbumStore.add(assetID: asset, to: ribbon, authorID: authorID, in: context)
        }

        // 缘的开始 ("the start of fate") — the earliest two days.
        let fate = AlbumStore.create(name: "缘的开始", authorID: authorID, in: context)
        fate.caption = "从第一次遇见开始的一切"
        for asset in [laughing[0], alley[0], alley[1]] {
            AlbumStore.add(assetID: asset, to: fate, authorID: authorID, in: context)
        }

        // TBD — genuinely nothing filed here. "To be decided" is the one
        // album name that gets to mean it: the empty state is the point of
        // this album, not an accident of the fixture.
        AlbumStore.create(name: "TBD", authorID: authorID, in: context)

        // 2024·春 ("2024, spring") — spans three of the four days, so its
        // detail view shows several date sections on its own. `alley[0]` is
        // added first here and is *also* in 缘的开始 above — the deliberately
        // double-filed photo. `coast[4]`, added last, is the newest member.
        // The cover is then set to `alley[0]` explicitly, so the hero and
        // "newest member" disagree on purpose — that gap is the entire
        // reason `Album.coverAssetID` exists rather than every album just
        // showing whatever was filed most recently.
        let spring = AlbumStore.create(name: "2024·春", authorID: authorID, in: context)
        spring.caption = "spring, in no particular order 春天的照片"
        for asset in [alley[0], groceries[1], groceries[2], coast[4]] {
            AlbumStore.add(assetID: asset, to: spring, authorID: authorID, in: context)
        }
        AlbumStore.setCover(spring, to: alley[0], in: context)
    }
}
#endif
