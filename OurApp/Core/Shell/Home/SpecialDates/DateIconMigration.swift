import Foundation
import SwiftData

/// One-time fill of `iconID` from the retired `emoji` field.
///
/// Unlike `AnniversaryMigration` this cannot lose anything: it writes into a
/// field that is empty by definition and never clears the source. The worst a
/// bad mapping does is put the wrong picture on a row, which is one tap to fix.
enum DateIconMigration {
    static func runIfNeeded(in container: ModelContainer) {
        let context = ModelContext(container)
        // Empty id == never migrated. A row the user has since given an icon
        // has a non-empty id and is not touched.
        //
        // `== ""` rather than `.isEmpty`: SwiftData can't translate `isEmpty`
        // into a fetch, so the query silently matched nothing and the migration
        // did nothing at all — which the tests caught only because they assert
        // the resulting icons rather than just the row count.
        let descriptor = FetchDescriptor<SpecialDate>(
            predicate: #Predicate { $0.iconID == "" })
        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }

        for date in pending {
            date.iconID = DateIcon.matching(emoji: date.emoji).rawValue
        }
        try? context.save()
    }
}
