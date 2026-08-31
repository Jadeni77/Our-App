import CryptoKit
import Foundation

/// A UUID derived from a string, the same way, forever.
///
/// For records whose identity *is* their content: a photo's asset id, a
/// membership's album-plus-asset. Two phones filing one picture into one album
/// must produce one row, not two that can never be reconciled — the property
/// whose absence left co-op matches duplicated and both players waiting.
///
/// **Not `hashValue`.** Swift seeds that per process, so it differs between
/// launches and between devices — the one thing an id like this must never do.
enum DerivedUUID {
    static func from(_ string: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(string.utf8)).prefix(16))
        // Version 4 shape and the RFC 4122 variant, so it is a well-formed
        // UUID rather than sixteen bytes wearing a costume.
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
