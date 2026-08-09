import SwiftUI

/// The hub's own art vocabulary (P16 follow-on): one icon per topic tile,
/// drawn in code so it belongs to us rather than to Apple's emoji font
/// (principle 9).
///
/// A closed enum rather than a view-factory closure — unlike `HubEntry`'s
/// badge, which is type-erased so Home never learns a sub-page's data types,
/// these three are defined together and only ever rendered by `HubIconView`.
enum HubIcon: CaseIterable {
    case specialDates, dailyQuestion, memories

    /// Light → mid → deep. The **mid stop is the `Theme` token itself**; the two
    /// ends are hand-tuned around it.
    ///
    /// Deriving the ends programmatically (mix toward white and toward
    /// `Theme.indigo`) was tried and reverted: it turned the heart mauve and
    /// drained the separation between the three icons. Hue ramps are a
    /// judgement, not an arithmetic mean.
    ///
    /// The cost of that choice, stated so it isn't a surprise: **if `Theme`'s
    /// palette is ever re-tuned (as it was in P8), these six literals must be
    /// re-tuned with it.** Nothing in the build will catch the drift.
    var ramp: (light: Color, mid: Color, deep: Color) {
        switch self {
        case .specialDates:
            (light: Color(red: 0.98, green: 0.78, blue: 0.86),
             mid: Theme.rose,
             deep: Color(red: 0.84, green: 0.47, blue: 0.62))
        case .dailyQuestion:
            (light: Color(red: 0.75, green: 0.69, blue: 0.93),
             mid: Theme.violet,
             deep: Color(red: 0.47, green: 0.45, blue: 0.75))
        case .memories:
            // Peach is the palette's lightest stop, so here it *is* the light
            // end and the ramp deepens into apricot.
            (light: Theme.peach,
             mid: Color(red: 0.97, green: 0.74, blue: 0.60),
             deep: Color(red: 0.89, green: 0.59, blue: 0.45))
        }
    }
}
