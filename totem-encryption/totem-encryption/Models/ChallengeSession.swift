//
//  ChallengeSession.swift
//  totem-encryption
//
//  Created by Charles Love on 4/20/26.
//
//  Represents a single authentication challenge issued by a website / relying party.
//  Flow:
//    Website → generates ChallengeSession (id + origin + nonce)
//    App     → scans totem object → derives key → signs nonce → sends ChallengeResponse
//    Website → verifies signature → grants access

import Foundation
import CryptoKit

// MARK: - Challenge Status

enum ChallengeStatus: String, Codable, Equatable {
    case pending    // waiting for user to approve / scan
    case approved   // user scanned correct object and signed successfully
    case denied     // user attempted but key was wrong
    case expired    // TTL elapsed before approval
}

// MARK: - Challenge Session

struct ChallengeSession: Identifiable, Codable, Equatable {

    /// Unique challenge identifier (UUID).
    let id: UUID

    /// The website / service requesting authentication (e.g. "myapp.com").
    let origin: String

    /// Random 32-byte nonce the app must sign. Server verifies this.
    let nonce: Data

    /// ISO-8601 creation timestamp.
    let issuedAt: Date

    /// Seconds until the challenge expires.
    let ttl: TimeInterval

    /// Current status.
    var status: ChallengeStatus

    /// Signed response sent back to the server (set after approval).
    var signedResponse: Data?

    // MARK: - Computed

    var expiresAt: Date { issuedAt.addingTimeInterval(ttl) }

    var isExpired: Bool { Date() >= expiresAt }

    var secondsRemaining: Int {
        max(0, Int(expiresAt.timeIntervalSinceNow))
    }

    // MARK: - Init (issued by server or generated locally for testing)

    init(
        id: UUID = UUID(),
        origin: String,
        nonce: Data = generateNonce(),
        issuedAt: Date = Date(),
        ttl: TimeInterval = 30,
        status: ChallengeStatus = .pending,
        signedResponse: Data? = nil
    ) {
        self.id = id
        self.origin = origin
        self.nonce = nonce
        self.issuedAt = issuedAt
        self.ttl = ttl
        self.status = status
        self.signedResponse = signedResponse
    }

    // MARK: - QR payload

    /// The compact payload encoded into a QR code by the website.
    /// Format: totem://challenge?id=<UUID>&origin=<origin>&nonce=<hex>&ttl=<seconds>
    var qrURL: URL? {
        var comps = URLComponents()
        comps.scheme = "totem"
        comps.host = "challenge"
        comps.queryItems = [
            URLQueryItem(name: "id",     value: id.uuidString),
            URLQueryItem(name: "origin", value: origin),
            URLQueryItem(name: "nonce",  value: nonce.hexString),
            URLQueryItem(name: "ttl",    value: String(Int(ttl)))
        ]
        return comps.url
    }

    /// Parse a ChallengeSession from a scanned QR URL.
    static func from(url: URL) -> ChallengeSession? {
        guard
            url.scheme == "totem",
            url.host == "challenge",
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let items = comps.queryItems
        else { return nil }

        let dict = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, String)? in
            guard let v = item.value else { return nil }
            return (item.name, v)
        })

        guard
            let idStr   = dict["id"],   let id     = UUID(uuidString: idStr),
            let origin  = dict["origin"],
            let nonceHex = dict["nonce"], let nonce = Data(hexString: nonceHex),
            let ttlStr  = dict["ttl"],  let ttl    = TimeInterval(ttlStr)
        else { return nil }

        return ChallengeSession(id: id, origin: origin, nonce: nonce, ttl: ttl)
    }
}

// MARK: - Nonce generation

private func generateNonce() -> Data {
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return Data(bytes)
}

// MARK: - ChallengeResponse (sent back to server)

struct ChallengeResponse: Codable {
    let challengeID: UUID
    let signature: Data     // HMAC-SHA256(nonce, derivedKey)
    let timestamp: Date
}

// MARK: - Data hex helpers

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    init?(hexString: String) {
        let hex = hexString
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index ..< next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
