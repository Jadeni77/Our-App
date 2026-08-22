import Foundation

/// Which way up a co-op screen wants to be.
///
/// **A deliberate exception to M13**, which rotates the whole Moonshot module
/// as one coherent landscape space. That is right for playing: the level is
/// authored wide and you hold the phone to suit it.
///
/// It is wrong for co-op's menus. Co-op is the part of this game you open to
/// find out whether it is your turn — a glance, from wherever you are, most
/// often not while sitting down to play. Turning the phone sideways to read
/// four words is a tax on the one interaction the mode exists for.
///
/// So the lobby and the waiting screen stand up, and the phone turns only for
/// the two things that genuinely need the width: taking your shot, and watching
/// theirs.
///
/// A free function rather than a line inside a view body, because it is the
/// rule and the rule is worth being able to state and test on its own.
enum CoopOrientation {
    static func needed(playing: Bool, watching: Bool) -> ModuleOrientation {
        playing || watching ? .landscape : .portrait
    }
}
