import Foundation

/// What two phones say to each other. Deliberately one round trip: connect,
/// ask, receive, close. Nothing is held open, so a peer disappearing mid-sync
/// costs one retry rather than a stuck connection.
enum SyncWire {
    /// What actually goes on the wire: a request plus proof it came from the
    /// phone we paired with. `proof` is absent only for `.pair`, which is the
    /// one request made *before* there is a secret to sign with.
    struct Message: Codable, Equatable {
        var request: Request
        var proof: SyncAuth.Proof?
    }

    enum Request: Codable, Equatable {
        /// The one-time code, exchanged for a real secret.
        case pair(code: String)
        /// `cursor` is author → last sequence this device already has.
        case records(cursor: [String: Int])
        /// Photo bytes, asked for only once the record naming them has arrived.
        case asset(id: String)
    }

    enum Response: Codable, Equatable {
        case paired(secret: Data)
        /// Wrong code, expired offer, or a request that couldn't prove itself.
        /// Deliberately one answer for all three: telling a caller *why* it was
        /// refused tells an attacker which part to work on.
        case denied
        case records(authorID: String, entries: [Entry])
        /// `nil` when the peer doesn't hold it — normal, not a failure.
        case asset(data: Data?)

        struct Entry: Codable, Equatable {
            var sequence: Int
            var envelope: SyncEnvelope
        }
    }
}

/// Length-prefixed framing: 4 bytes big-endian, then the payload.
///
/// TCP is a stream, not a message queue — without framing, two envelopes sent
/// back to back arrive as one buffer and neither decodes, and a large one
/// arrives in pieces that each fail to decode on their own.
enum SyncFraming {
    static func frame(_ payload: Data) -> Data {
        var length = UInt32(payload.count).bigEndian
        var out = Data(bytes: &length, count: 4)
        out.append(payload)
        return out
    }

    /// Pops one complete message off the front of `buffer`, or returns nil if
    /// it hasn't all arrived yet.
    static func nextMessage(from buffer: inout Data) -> Data? {
        guard buffer.count >= 4 else { return nil }
        let length = buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard buffer.count >= 4 + Int(length) else { return nil }
        let payload = buffer.subdata(in: 4..<(4 + Int(length)))
        buffer.removeSubrange(0..<(4 + Int(length)))
        return payload
    }
}
