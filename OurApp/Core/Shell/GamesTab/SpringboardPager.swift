import Foundation

/// S8: the springboard auto-flows the flat ordered layout into fixed-capacity
/// horizontal pages, like the real home screen. The flat list stays the
/// model — pages are pure presentation, so these are plain functions the
/// view calls every render (and tests call directly).
enum SpringboardPager {
    /// Tiles per page: the whole rows that fit the height, never fewer than
    /// one row. Degenerate measurements (first render, zero sizes) fail soft
    /// to a single row rather than a broken page.
    static func capacity(columns: Int, availableHeight: CGFloat,
                         tileHeight: CGFloat, rowSpacing: CGFloat) -> Int {
        guard columns > 0 else { return 0 }
        guard tileHeight > 0 else { return columns }
        let rows = Int((availableHeight + rowSpacing) / (tileHeight + rowSpacing))
        return max(1, rows) * columns
    }

    /// Chunks in order; the last page holds the remainder. No items, no pages.
    static func pages<Item>(of items: [Item], capacity: Int) -> [[Item]] {
        guard !items.isEmpty else { return [] }
        guard capacity > 0 else { return [items] }
        return stride(from: 0, to: items.count, by: capacity).map {
            Array(items[$0 ..< min($0 + capacity, items.count)])
        }
    }

    /// Pages while a reorder drag is live: the preview order opens a gap at
    /// `insertAt` (the gap is the dragged tile itself, rendered invisible) —
    /// but the dragged tile never leaves the page its drag began on. Its
    /// hosting view owns the live gesture; letting another page's ForEach
    /// adopt it would tear that view down and cancel the drag mid-flight.
    /// The preview slot is therefore clamped into the origin page's index
    /// window: moving an element only *within* that window means every other
    /// page — and the page count — stays byte-identical to the resting
    /// layout. A preview slot on another page shows no gap there until
    /// release, which still lands at the real index.
    static func previewPages(items: [GamesLayout.Item],
                             dragged: GamesLayout.ItemID,
                             insertAt: Int,
                             capacity: Int,
                             originPage: Int) -> [[GamesLayout.Item]] {
        guard let draggedItem = items.first(where: { $0.id == dragged }) else {
            return pages(of: items, capacity: capacity)
        }
        var flat = items.filter { $0.id != dragged }
        guard capacity > 0 else {
            flat.insert(draggedItem, at: min(max(insertAt, 0), flat.count))
            return pages(of: flat, capacity: capacity)
        }
        let lastPage = (items.count - 1) / capacity
        let origin = min(max(originPage, 0), lastPage)
        let lower = origin * capacity
        let upper = min(lower + capacity, items.count) - 1
        flat.insert(draggedItem, at: min(max(insertAt, lower), upper))
        return pages(of: flat, capacity: capacity)
    }
}
