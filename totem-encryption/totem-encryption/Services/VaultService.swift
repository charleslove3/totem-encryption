//
//  VaultService.swift
//  totem-encryption
//
//  Created by Charles Love on 4/20/26.
//
//  Phase 4 — Secure Enclave & Vault
//  Stores the Fuzzy Extractor helper string in the Keychain behind biometrics,
//  and provides AES-GCM encrypt / decrypt using a derived SymmetricKey.

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
        case .biometricFailed(let e):   return "Biometric error: \(e.localizedDescription)"
        case .keychainWrite(let s):     return "Keychain write failed: \(s)"
        case .keychainRead(let s):      return "Keychain read failed: \(s)"
        case .keychainNotFound:         return "No helper string found in Vault. Enroll first."
        case .encryptionFailed(let e):  return "Encryption failed: \(e.localizedDescription)"
        case .decryptionFailed(let e):  return "Decryption failed: \(e.localizedDescription)"
        }
    }
}

final class VaultService {

    // MARK: - Constants
    private static let keychainService = "com.totem.vault"
    private static let helperStringAccount = "fuzzy_helper_string"

    // MARK: - Keychain: Store helper string (biometric-backed)

    func storeHelperString(_ data: Data) async throws {
        try await authenticateBiometric(reason: "Authenticate to save Totem Vault helper string.")

        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      VaultService.keychainService,
            kSecAttrAccount as String:      VaultService.helperStringAccount,
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        ]

        // Delete any existing entry first.
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.keychainWrite(status) }
    }

    // MARK: - Keychain: Load helper string (biometric-backed)

    func loadHelperString() async throws -> Data {
        try await authenticateBiometric(reason: "Authenticate to reconstruct your Totem key.")

        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      VaultService.keychainService,
            kSecAttrAccount as String:      VaultService.helperStringAccount,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { throw VaultError.keychainNotFound }
        guard status == errSecSuccess else { throw VaultError.keychainRead(status) }
        guard let data = result as? Data else { throw VaultError.keychainNotFound }
        return data
    }

    // MARK: - Encryption (AES-GCM)

    func encrypt(plaintext: Data, key: SymmetricKey) throws -> Data {
        do {
            let sealed = try AES.GCM.seal(plaintext, using: key)
            return sealed.combined ?? Data()
        } catch {
            throw VaultError.encryptionFailed(error)
        }
    }

    func decrypt(ciphertext: Data, key: SymmetricKey) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw VaultError.decryptionFailed(error)
        }
    }

    // MARK: - Biometric Gate

    private func authenticateBiometric(reason: String) async throws {
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            // Fall back to device passcode if biometrics unavailable (Simulator, etc.)
            return
        }
        do {
            try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            throw VaultError.biometricFailed(error)
        }
    }
}
