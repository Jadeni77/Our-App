import CryptoKit
import Foundation
import Testing
@testable import OurApp

struct SyncPairingTests {
    @Test func aCodeIsSixDigitsAndSecretsDiffer() {
        let code = SyncPairing.makeCode()
        #expect(code.count == SyncPairing.codeLength)
        // Computed outside the macro: `allSatisfy` is `rethrows`, and `#expect`
        // treats that as throwing (same trap as HubCatalogTests).
        let allDigits = code.allSatisfy(\.isNumber)
        #expect(allDigits)
        #expect(SyncPairing.makeSecret() != SyncPairing.makeSecret())
        #expect(SyncPairing.makeSecret().count == 32)
    }

    @Test func theRightCodeYieldsTheSecret() {
        var offer = SyncPairing.Offer()
        #expect(offer.claim(offer.code) == offer.secret)
    }

    @Test func aWrongCodeYieldsNothingAndBurnsAnAttempt() {
        var offer = SyncPairing.Offer(code: "123456")
        #expect(offer.claim("000000") == nil)
        #expect(offer.attempts == 1)
    }

    @Test func guessingRunsOutOfAttempts() {
        var offer = SyncPairing.Offer(code: "123456")
        for _ in 0..<SyncPairing.maxAttempts { _ = offer.claim("000000") }

        // Five guesses at one in a million, then the offer is dead — the right
        // code stops working too, so a burnt offer can't be salvaged by luck.
        #expect(offer.isLive() == false)
        #expect(offer.claim("123456") == nil)
    }

    @Test func anExpiredOfferYieldsNothingEvenWithTheRightCode() {
        let made = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var offer = SyncPairing.Offer(code: "123456", createdAt: made)
        let later = made.addingTimeInterval(SyncPairing.codeLifetime + 1)

        #expect(offer.claim("123456", at: later) == nil)
    }

    @Test func aCodeOfTheWrongLengthIsRejected() {
        var offer = SyncPairing.Offer(code: "123456")
        #expect(offer.claim("12345") == nil)
        #expect(offer.claim("1234567") == nil)
    }
}

struct SyncAuthTests {
    private let secret = SyncPairing.makeSecret()
    private let body = Data("give me your memories".utf8)

    @Test func aSignedRequestVerifies() {
        let proof = SyncAuth.sign(body, secret: secret)
        #expect(SyncAuth.verify(proof, body: body, secret: secret))
    }

    @Test func anotherPhonesSecretDoesNotVerify() {
        let proof = SyncAuth.sign(body, secret: secret)
        // The whole point: a stranger on the same wifi speaks the protocol
        // fluently and still gets nothing.
        #expect(SyncAuth.verify(proof, body: body, secret: SyncPairing.makeSecret()) == false)
    }

    @Test func aTamperedBodyDoesNotVerify() {
        let proof = SyncAuth.sign(body, secret: secret)
        #expect(SyncAuth.verify(proof, body: Data("give me everything".utf8),
                                secret: secret) == false)
    }

    @Test func anOldRequestDoesNotVerify() {
        let signedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let proof = SyncAuth.sign(body, secret: secret, at: signedAt)

        // Captured today, replayed tomorrow: the timestamp is inside the MAC,
        // so it can't be refreshed without the secret.
        #expect(SyncAuth.verify(proof, body: body, secret: secret,
                                at: signedAt.addingTimeInterval(SyncAuth.window + 1)) == false)
        #expect(SyncAuth.verify(proof, body: body, secret: secret,
                                at: signedAt.addingTimeInterval(30)))
    }

    @Test func aReplayWithAFreshTimestampDoesNotVerify() {
        let signedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var proof = SyncAuth.sign(body, secret: secret, at: signedAt)
        proof.timestamp = signedAt.addingTimeInterval(SyncAuth.window * 2)

        #expect(SyncAuth.verify(proof, body: body, secret: secret,
                                at: proof.timestamp) == false)
    }
}
