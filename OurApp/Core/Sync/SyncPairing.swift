import CryptoKit
import Foundation

/// Two phones agreeing, once, that they belong together.
///
/// **Why this exists at all:** before it, `LocalPeerService` answered any
/// connection that spoke the protocol. That was survivable only because sync
/// was behind a switch you turned on deliberately. Making sync invisible —
/// which is what it should be — means the phone advertises on *every* network
/// it joins, so "anyone on this wifi can ask for your memories" stops being
/// theoretical.
///
/// The shape: one phone shows a six-digit code, the other types it. The code is
/// a one-time channel for handing over a real 256-bit secret; everything
/// afterwards is signed with that secret and the code is never used again.
enum SyncPairing {
    /// Short enough to type, and it only has to survive a two-minute window
    /// with five attempts — an attacker gets five guesses at one in a million
    /// while you are stood there pairing. Stated rather than implied: this is
    /// not protection against a determined attacker with unlimited attempts,
    /// which is what the window and the attempt cap exist to prevent.
    static let codeLength = 6
    static let codeLifetime: TimeInterval = 120
    static let maxAttempts = 5

    static func makeCode() -> String {
        (0..<codeLength).map { _ in String(Int.random(in: 0...9)) }.joined()
    }

    static func makeSecret() -> Data {
        Data(SymmetricKey(size: .bits256).withUnsafeBytes(Array.init))
    }

    /// An offer this phone is currently making. One at a time, deliberately:
    /// two live codes would double an attacker's chances for no benefit.
    struct Offer: Equatable {
        let code: String
        let secret: Data
        let createdAt: Date
        private(set) var attempts = 0

        init(code: String = makeCode(), secret: Data = makeSecret(), createdAt: Date = .now) {
            self.code = code
            self.secret = secret
            self.createdAt = createdAt
        }

        func isLive(at moment: Date = .now) -> Bool {
            attempts < maxAttempts && moment.timeIntervalSince(createdAt) < codeLifetime
        }

        /// Counts a failed attempt made without a successful `claim` — a
        /// wrong-length code, say. Without it, malformed guesses would be free.
        mutating func burnAttempt() {
            attempts += 1
        }

        /// - Returns: the secret when the code matches and the offer is still
        ///   live, otherwise nil. Always consumes an attempt, so guessing costs
        ///   the guesser something.
        mutating func claim(_ candidate: String, at moment: Date = .now) -> Data? {
            guard isLive(at: moment) else { return nil }
            attempts += 1
            // Constant-time: a comparison that returns early leaks how much of
            // the code was right, which turns a million guesses into sixty.
            guard candidate.utf8.count == code.utf8.count else { return nil }
            var difference: UInt8 = 0
            for (lhs, rhs) in zip(candidate.utf8, code.utf8) { difference |= lhs ^ rhs }
            return difference == 0 ? secret : nil
        }
    }
}

/// Proof that a request comes from the phone we paired with.
///
/// Every request carries a nonce, a timestamp and an HMAC over both plus the
/// body. The timestamp window is what stops a captured request being replayed
/// tomorrow; it does not need to be long, because both phones are on one
/// network and a request is answered in milliseconds.
enum SyncAuth {
    static let window: TimeInterval = 60

    struct Proof: Codable, Equatable {
        var nonce: String
        var timestamp: Date
        var mac: Data
    }

    static func sign(_ body: Data, secret: Data, at moment: Date = .now) -> Proof {
        let nonce = UUID().uuidString
        return Proof(nonce: nonce, timestamp: moment,
                     mac: mac(body: body, nonce: nonce, timestamp: moment, secret: secret))
    }

    static func verify(_ proof: Proof, body: Data, secret: Data, at moment: Date = .now) -> Bool {
        guard abs(moment.timeIntervalSince(proof.timestamp)) <= window else { return false }
        let expected = mac(body: body, nonce: proof.nonce,
                           timestamp: proof.timestamp, secret: secret)
        // `HMAC.isValidAuthenticationCode` is constant-time; `==` on Data is not.
        return HMAC<SHA256>.isValidAuthenticationCode(
            proof.mac, authenticating: signedBytes(body: body, nonce: proof.nonce,
                                                   timestamp: proof.timestamp),
            using: SymmetricKey(data: secret)) && expected.count == proof.mac.count
    }

    private static func mac(body: Data, nonce: String, timestamp: Date, secret: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(
            for: signedBytes(body: body, nonce: nonce, timestamp: timestamp),
            using: SymmetricKey(data: secret)))
    }

    /// The nonce and timestamp are *inside* the signed bytes. Signing only the
    /// body would let anyone replay a captured request with a fresh timestamp.
    private static func signedBytes(body: Data, nonce: String, timestamp: Date) -> Data {
        var bytes = Data(nonce.utf8)
        bytes.append(Data(String(timestamp.timeIntervalSince1970).utf8))
        bytes.append(body)
        return bytes
    }
}
