//
//  AuthenticatorService.swift
//  totem-encryption
//
//  Created by Charles Love on 4/20/26.
//
//  Orchestrates the full authentication flow:
//    1. Receive a ChallengeSession (from QR scan or simulated).
//    2. Reconstruct the 256-bit key from physical sensors (LiDAR + magnetic).
//    3. Sign the challenge nonce with HMAC-SHA256 using the derived key.
//    4. Return a ChallengeResponse for the relying party to verify.
//
//  In the full implementation the response is POSTed to the server via URLSession.
//  Until the phone is connected, this service runs entirely locally so all
//  flows can be designed and tested in the simulator.

import CryptoKit
import Foundation

enum AuthenticatorError: LocalizedError {
    case challengeExpired
    case noPhysicalData
    case signingFailed(Error)
    case networkFailed(Error)

    var errorDescription: String? {
        switch self {
        case .challengeExpired:         return "Challenge has expired. Request a new one."
        case .noPhysicalData:           return "No LiDAR or magnetic data captured yet. Scan your totem first."
        case .signingFailed(let e):     return "Signing failed: \(e.localizedDescription)"
        case .networkFailed(let e):     return "Network error: \(e.localizedDescription)"
        }
    }
}

@MainActor
final class AuthenticatorService: ObservableObject {

    // MARK: - Published State
    @Published var sessions: [ChallengeSession] = []
    @Published var statusMessage = "Ready"

    // MARK: - Dependencies
    private let vault = VaultService()

    // MARK: - Public API

    /// Add a new challenge (from QR scan or simulated).
    func receive(challenge: ChallengeSession) {
        // Remove any existing challenge from the same origin.
        sessions.removeAll { $0.origin == challenge.origin }
        sessions.insert(challenge, at: 0)
        statusMessage = "Challenge received from \(challenge.origin)"
        scheduleExpiry(for: challenge)
    }

    /// Generate a local test challenge — useful before connecting to a real server.
    func generateTestChallenge(origin: String = "demo.totem.app") -> ChallengeSession {
        let session = ChallengeSession(origin: origin, ttl: 30)
        receive(challenge: session)
        return session
    }

    /// Approve a challenge: reconstruct key from sensor data, sign nonce, mark approved.
    func approve(
        challengeID: UUID,
        cloud: PointCloud?,
        magnetic: MagneticSignature? = nil
    ) async {
        guard var session = session(id: challengeID) else { return }
        guard !session.isExpired else {
            update(challengeID: challengeID, status: .expired)
            statusMessage = "Challenge expired."
            return
        }
        guard let cloud else {
            statusMessage = AuthenticatorError.noPhysicalData.localizedDescription
            update(challengeID: challengeID, status: .denied)
            return
        }

        statusMessage = "Reconstructing key…"

        // Try every enrolled slot until one produces a valid signature
        let seed = FuzzyExtractor.buildSeed(cloud: cloud)
        var signed = false
        for slot in TotemSlot.allCases where vault.isEnrolled(slot) {
            guard let helper = try? vault.loadHelperNoAuth(for: slot),
                  let key = try? FuzzyExtractor.reconstruct(noisySeedData: seed, helperString: helper)
            else { continue }
            let signature = signNonce(session.nonce, with: key)
            session.status = .approved
            session.signedResponse = signature
            update(session: session)
            statusMessage = "Approved ✓ — \(session.origin) (via \(slot.displayName))"
            signed = true
            break
        }
        if !signed {
            update(challengeID: challengeID, status: .denied)
            statusMessage = "Denied ✗ — no matching object"
        }
    }

    /// Deny a challenge manually.
    func deny(challengeID: UUID) {
        update(challengeID: challengeID, status: .denied)
        statusMessage = "Denied ✗"
    }

    // MARK: - Private Helpers

    private func signNonce(_ nonce: Data, with key: SymmetricKey) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: nonce, using: key)
        return Data(mac)
    }

    private func session(id: UUID) -> ChallengeSession? {
        sessions.first { $0.id == id }
    }

    private func update(challengeID: UUID, status: ChallengeStatus) {
        if let idx = sessions.firstIndex(where: { $0.id == challengeID }) {
            sessions[idx].status = status
        }
    }

    private func update(session: ChallengeSession) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        }
    }

    /// Auto-mark session as expired after its TTL.
    private func scheduleExpiry(for session: ChallengeSession) {
        let delay = session.expiresAt.timeIntervalSinceNow
        guard delay > 0 else { return }
        Task {
            try? await Task.sleep(for: .seconds(delay))
            if let current = self.session(id: session.id), current.status == .pending {
                self.update(challengeID: session.id, status: .expired)
                self.statusMessage = "Challenge from \(session.origin) expired."
            }
        }
    }

    // MARK: - (Future) Network submission

    // private func submitResponse(_ response: ChallengeResponse) async throws {
    //     let url = URL(string: "https://your-relay-server.com/verify")!
    //     var req = URLRequest(url: url)
    //     req.httpMethod = "POST"
    //     req.httpBody = try JSONEncoder().encode(response)
    //     req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    //     let (_, _) = try await URLSession.shared.data(for: req)
    // }
}
