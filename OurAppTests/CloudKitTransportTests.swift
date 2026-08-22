import CloudKit
import Foundation
import Testing
@testable import OurApp

/// What can be proven about the CloudKit transport without a network.
///
/// Not much, and that is the design: everything decidable offline lives in
/// `CloudKitEnvelopeCodec` where it is tested properly, so what remains here is
/// the part only two real phones can prove. These tests pin the edges of it —
/// the ones where being wrong fails silently rather than loudly.
struct CloudKitTransportTests {
    private let zoneID = CKRecordZone.ID(zoneName: "Couple", ownerName: CKCurrentUserDefaultName)

    private func transport(scope: CKDatabase.Scope = .shared) -> CloudKitTransport {
        CloudKitTransport(database: CKContainer(identifier: "iCloud.test").database(with: scope),
                          zoneID: zoneID)
    }

    /// **A bad token must mean "start from the beginning", never "you are up to
    /// date".** Reading it the other way is how a phone silently stops
    /// receiving anything — which this project has now shipped twice, once with
    /// a push watermark and once with a pull cursor.
    @Test func anUnreadableTokenStartsFromTheBeginning() {
        #expect(CloudKitTransport.token(from: nil) == nil)
        #expect(CloudKitTransport.token(from: "") == nil)
        #expect(CloudKitTransport.token(from: "not base64 at all !!") == nil)
        // Well-formed base64 of something that is not a change token.
        #expect(CloudKitTransport.token(from: Data("hello".utf8).base64EncodedString()) == nil)
    }

    /// Progress through the private database says nothing about the shared one:
    /// one is this phone's backup, the other is the couple's timeline.
    @Test func eachScopeAndZoneRemembersItsOwnProgress() {
        let shared = transport(scope: .shared).syncIdentity
        let private_ = transport(scope: .private).syncIdentity
        #expect(shared != private_)

        let otherZone = CloudKitTransport(
            database: CKContainer(identifier: "iCloud.test").database(with: .shared),
            zoneID: CKRecordZone.ID(zoneName: "Other", ownerName: CKCurrentUserDefaultName))
        #expect(otherZone.syncIdentity != shared)
    }

    /// It has to be a `SyncTransport` and nothing more, or the engine would
    /// need to know which transport it is holding.
    @Test func itIsJustATransport() {
        let any: any SyncTransport = transport()
        #expect(any.syncIdentity.hasPrefix("cloudkit:"))
    }
}

/// The zone the couple shares.
@MainActor
struct CoupleZoneTests {
    /// **A custom zone, because the default zone cannot be shared.** If this
    /// ever became the default zone, sharing would fail at runtime on a real
    /// account with an error nobody would connect to this line.
    @Test func theZoneIsNamedAndNotTheDefault() {
        #expect(CoupleZone.ownedZoneID.zoneName == "Couple")
        #expect(CoupleZone.ownedZoneID != CKRecordZone.default().zoneID)
    }

    /// The owner and the accepter must end up on the *same* zone, reached from
    /// two different databases. Getting this backwards means two people each
    /// writing happily into a zone the other never reads — the exact failure
    /// this whole branch has been about.
    @Test func theOwnedZoneCarriesTheCurrentUserAsItsOwner() {
        #expect(CoupleZone.ownedZoneID.ownerName == CKCurrentUserDefaultName)
    }

    /// The transport's identity has to distinguish the two sides of the share,
    /// or one phone's progress bookmark would be applied to the other's zone.
    @Test func eachSideOfTheShareKeepsItsOwnBookmark() {
        let container = CKContainer(identifier: CoupleZone.containerID)
        let mine = CloudKitTransport(database: container.privateCloudDatabase,
                                     zoneID: CoupleZone.ownedZoneID)
        let theirs = CloudKitTransport(
            database: container.sharedCloudDatabase,
            zoneID: CKRecordZone.ID(zoneName: CoupleZone.zoneName, ownerName: "_someoneElse"))
        #expect(mine.syncIdentity != theirs.syncIdentity)
    }
}
