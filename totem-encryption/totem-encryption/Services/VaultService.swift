//
//  VaultService.swift
//  totem-encryption
//
//  Multi-slot Vault. Each TotemSlot gets its own Keychain helper string.
//  The same encrypted payload is stored once. Any one slot's key can decrypt it.

import CryptoKit
import Foundation
import LocalAuthentication
import Security

enum VaultError: LocalizedError {
    case biometricFailed(Error)
    case keychainWrite(OSStatus)
    case keychainRead(OSStatus)
    case keychainNotFound
    case encryptionFailed(Error)
    case decryptionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .biometricFailed(let e):  return "Biometric error: \(e.localizedDescription)"
        case .keychainWrite(let s):    return "Keychain write failed (OSStatus \(s))"
        case .keychainRead(let s):     return "Keychain read failed (OSStatus \(s))"
        case .keychainNotFound:        return "Nothing enrolled yet. Set up your objects first."
        case .encryptionFailed(let e): return "Encryption failed: \(e.localizedDescription)"
        case .decryptionFailed(let e): return "Decryption failed: \(e.localizedDescription)"
        }
    }
}

final class VaultService {

    private static let service    = "com.totem.vault"
    private static let payloadKey = "totem_payload"

    // MARK: - Helper string (per slot)

    func storeHelper(_ data: Data, for slot: TotemSlot) async throws {
        try await authenticateBiometric(reason: "Save your \(slot.displayName) object to Vault.")
        let query: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    Self.service,
            kSecAttrAccount as String:    slot.keychainAccount,
            kSecValueData as String:      data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.keychainWrite(status) }
        UserDefaults.standard.set(true, forKey: slot.enrolledKey)
    }

    func loadHelperNoAuth(for slot: TotemSlot) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: slot.keychainAccount,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw VaultError.keychainNotFound }
        guard status == errSecSuccess, let data = result as? Data else {
            throw VaultError.keychainRead(status)
        }
        return data
    }

    func deleteHelper(for slot: TotemSlot) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: slot.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: slot.enrolledKey)
    }

    func isEnrolled(_ slot: TotemSlot) -> Bool {
        UserDefaults.standard.bool(forKey: slot.enrolledKey)
    }

    var enrolledSlots: [TotemSlot] { TotemSlot.allCases.filter { isEnrolled($0) } }

    // MARK: - Payload (one shared encrypted blob)

    func storePayload(_ data: Data) {
        UserDefaults.standard.set(data, forKey: Self.payloadKey)
    }

    func loadPayload() -> Data? {
        UserDefaults.standard.data(forKey: Self.payloadKey)
    }

    // MARK: - AES-GCM

    func encrypt(plaintext: Data, key: SymmetricKey) throws -> Data {
        do {
            let sealed = try AES.GCM.seal(plaintext, using: key)
            return sealed.combined ?? Data()
        } catch { throw VaultError.encryptionFailed(error) }
    }

    func decrypt(ciphertext: Data, key: SymmetricKey) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(box, using: key)
        } catch { throw VaultError.decryptionFailed(error) }
    }

    // MARK: - Unlock: try every enrolled slot, return first match

    func tryUnlock(cloud: PointCloud) async throws -> (slot: TotemSlot, plaintext: Data) {
        guard let payload = loadPayload() else { throw VaultError.keychainNotFound }
        try await authenticateBiometric(reason: "Unlock your Totem.")
        let seed = FuzzyExtractor.buildSeed(cloud: cloud)
        for slot in TotemSlot.allCases where isEnrolled(slot) {
            guard let helper = try? loadHelperNoAuth(for: slot) else { continue }
            guard let key = try? FuzzyExtractor.reconstruct(noisySeedData: seed, helperString: helper) else { continue }
            if let plaintext = try? decrypt(ciphertext: payload, key: key) {
                return (slot, plaintext)
            }
        }
        throw VaultError.decryptionFailed(VaultError.keychainNotFound)
    }

    // MARK: - Biometric

    func authenticateBiometric(reason: String) async throws {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else { return }
        do {
            try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch {
            throw VaultError.biometricFailed(error)
        }
    }
}
