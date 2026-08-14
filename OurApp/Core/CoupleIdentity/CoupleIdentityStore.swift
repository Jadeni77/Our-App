import Foundation
import Observation
import UIKit

enum Partner: String, CaseIterable {
    case one, two
}

/// Couple identity in local settings (decision P6): names in UserDefaults,
/// avatar photos as image files on disk. The anniversary left with P17 — it is
/// a `SpecialDate` record now, so the value both phones must agree on already
/// lives in the store that will sync. No pairing/sync —
/// the data model is deliberately tiny so migrating into synced core data
/// later is mechanical (see DESIGN.md §7).
@MainActor
@Observable
final class CoupleIdentityStore {
    enum Keys {
        static let nameOne = "couple.nameOne"
        /// Read by `PartnerVoice` too, which needs the name without being able
        /// to touch this store — hence not private.
        static let nameTwo = "couple.nameTwo"
    }

    var nameOne: String {
        didSet { defaults.set(nameOne, forKey: Keys.nameOne) }
    }
    var nameTwo: String {
        didSet { defaults.set(nameTwo, forKey: Keys.nameTwo) }
    }
    /// This install's author id (P18). Nobody chooses it; see `LocalAuthor`.
    let authorID: String

    /// Which display slot a record's author belongs in. `Partner` survives as
    /// *this phone's* two slots — `.one` is always whoever holds it — rather
    /// than as a globally-agreed half of the couple, which is what made it
    /// answerable wrongly.
    func slot(for authorID: String) -> Partner {
        authorID == self.authorID ? .one : .two
    }
    private(set) var avatars: [Partner: UIImage] = [:]

    private let defaults: UserDefaults
    private let directory: URL

    /// `directory` is injectable for tests; the default is Application Support,
    /// which unlike Documents isn't user-visible in the Files app.
    init(defaults: UserDefaults = .standard,
         directory: URL? = nil,
         authorStorage: AuthorIDStorage = KeychainAuthorIDStorage()) {
        self.defaults = defaults
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoupleIdentity", isDirectory: true)

        nameOne = defaults.string(forKey: Keys.nameOne) ?? ""
        nameTwo = defaults.string(forKey: Keys.nameTwo) ?? ""
        authorID = LocalAuthor.id(defaults: defaults, storage: authorStorage)
        for partner in Partner.allCases {
            if let image = UIImage(contentsOfFile: avatarURL(for: partner).path) {
                avatars[partner] = image
            }
        }
    }

    func setAvatar(_ data: Data, for partner: Partner) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: avatarURL(for: partner), options: .atomic)
        avatars[partner] = UIImage(data: data)
    }

    private func avatarURL(for partner: Partner) -> URL {
        directory.appendingPathComponent("avatar-\(partner.rawValue).img")
    }
}
