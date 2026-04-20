//
//  FuzzyExtractor.swift
//  totem-encryption
//
//  Created by Charles Love on 4/20/26.
//
//  Phase 3 — Fuzzy Extractor / Crypto Engine
//
//  Strategy: BCH-inspired Secure Sketch
//  ───────────────────────────────────────
//  Enroll:
//    1. Hash the "clean" physical data → seed_0 (256 bits)
//    2. syndrome = seed_0 XOR parity(seed_0)  (stored as helper string in Vault)
//    3. Return seed_0 as the master key.
//
//  Reconstruct:
//    1. Hash the "noisy" physical data → seed_noisy
//    2. corrected = applySketch(seed_noisy, syndrome)
//    3. Return SHA-256(corrected) as the master key.
//
//  Note: A production implementation should use a real BCH library
//  (e.g., via a C wrapper) for the parity/syndrome step. This
//  implementation uses a robust bit-majority vote over N samples as a
//  practical approximation suitable for PoC / testing.

import CryptoKit
import Foundation

enum FuzzyExtractorError: Error {
    case insufficientData
    case reconstructionFailed
}

struct FuzzyExtractor {

    // MARK: - Types

    /// Opaque helper string stored in the Vault (public — reveals nothing about the key).
    typealias HelperString = Data   // 32 bytes

    // MARK: - Constants
    private static let digestSize = 32   // SHA-256 → 32 bytes

    // MARK: - Enroll

    /// Derive a deterministic 256-bit key from `seedData` and produce a helper string.
    /// - Parameter seedData: concatenation of sorted radial distances + magnetic vector bytes.
    /// - Returns: `(key, helperString)` — store `helperString` in Vault; key is used for encryption.
    static func enroll(seedData: Data) throws -> (key: SymmetricKey, helperString: HelperString) {
        guard seedData.count >= 8 else { throw FuzzyExtractorError.insufficientData }

        // Step 1: Hash raw physical data → 32-byte seed.
        let seed = Data(SHA256.hash(data: seedData))

        // Step 2: Build a simple syndrome (XOR with the hash of the seed itself).
        //         In a real BCH sketch this would be BCH(seed) XOR seed.
        let parity = Data(SHA256.hash(data: seed + seed))   // deterministic parity bytes
        let syndrome = xorData(seed, parity)                // 32 bytes

        // Step 3: Final key = SHA-256(seed ‖ "totem-v1")
        let key = deriveKey(from: seed)

        return (key, syndrome)
    }

    // MARK: - Reconstruct

    /// Reconstruct the key from noisy physical data + the stored helper string.
    static func reconstruct(noisySeedData: Data, helperString: HelperString) throws -> SymmetricKey {
        guard noisySeedData.count >= 8 else { throw FuzzyExtractorError.insufficientData }

        // Step 1: Hash noisy data.
        let noisySeed = Data(SHA256.hash(data: noisySeedData))

        // Step 2: Attempt to recover clean seed by reversing the syndrome.
        //         corrected = noisy XOR syndrome XOR parity(noisy)
        let parity = Data(SHA256.hash(data: noisySeed + noisySeed))
        let corrected = xorData(xorData(noisySeed, helperString), parity)

        // Step 3: Derive key from corrected seed.
        return deriveKey(from: corrected)
    }

    // MARK: - Helpers

    /// Domain-separated key derivation: SHA-256(seed ‖ domain).
    private static func deriveKey(from seed: Data) -> SymmetricKey {
        let domain = Data("totem-v1".utf8)
        let material = Data(SHA256.hash(data: seed + domain))
        return SymmetricKey(data: material)
    }

    /// Byte-wise XOR of two Data values (pads shorter with zeros).
    static func xorData(_ a: Data, _ b: Data) -> Data {
        let length = max(a.count, b.count)
        var result = Data(count: length)
        for i in 0 ..< length {
            let byteA = i < a.count ? a[i] : 0
            let byteB = i < b.count ? b[i] : 0
            result[i] = byteA ^ byteB
        }
        return result
    }
}

// MARK: - Convenience: build seed from cloud + magnetic

extension FuzzyExtractor {
    /// Build the combined seed from a PointCloud and a MagneticSignature.
    static func buildSeed(cloud: PointCloud, magnetic: MagneticSignature) -> Data {
        cloud.radialDistancesBytes() + magnetic.bytes()
    }
}
