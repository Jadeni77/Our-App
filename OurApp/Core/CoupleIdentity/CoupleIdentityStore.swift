import Foundation
import Observation
import UIKit

enum Partner: String, CaseIterable {
    case one, two
}

/// Couple identity in local settings (decision P6): names + anniversary in
/// UserDefaults, avatar photos as image files on disk. No pairing/sync —
/// the data model is deliberately tiny so migrating into synced core data
/// later is mechanical (see DESIGN.md §7).
@MainActor
@Observable
final class CoupleIdentityStore {
    private enum Keys {
        static let nameOne = "couple.nameOne"
        static let nameTwo = "couple.nameTwo"
        static let anniversary = "couple.anniversary"
    }

    var nameOne: String {
        didSet { defaults.set(nameOne, forKey: Keys.nameOne) }
    }
    var nameTwo: String {
        didSet { defaults.set(nameTwo, forKey: Keys.nameTwo) }
    }
    var anniversary: Date? {
        didSet {
            if let anniversary {
                defaults.set(anniversary.timeIntervalSinceReferenceDate, forKey: Keys.anniversary)
            } else {
                defaults.removeObject(forKey: Keys.anniversary)
            }
        }
    }
    private(set) var avatars: [Partner: UIImage] = [:]

    private let defaults: UserDefaults
    private let directory: URL

    /// `directory` is injectable for tests; the default is Application Support,
    /// which unlike Documents isn't user-visible in the Files app.
    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoupleIdentity", isDirectory: true)

        nameOne = defaults.string(forKey: Keys.nameOne) ?? ""
        nameTwo = defaults.string(forKey: Keys.nameTwo) ?? ""
        if defaults.object(forKey: Keys.anniversary) != nil {
            anniversary = Date(timeIntervalSinceReferenceDate: defaults.double(forKey: Keys.anniversary))
        }
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
