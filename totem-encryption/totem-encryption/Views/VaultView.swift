//
//  VaultView.swift
//  totem-encryption
//
//  Created by Charles Love on 4/20/26.
//
//  Phase 4 UI — Enroll (save helper string) and reconstruct key to encrypt / decrypt.

import SwiftUI
import CryptoKit

@MainActor
struct VaultView: View {

    // MARK: - Dependencies (injected via environment in real app; local for PoC)
    @State private var lidar = LiDARService()
    @State private var magnetic = MagneticService()
    private let vault = VaultService()

    // MARK: - State
    @State private var plaintext = ""
    @State private var ciphertext: Data?
    @State private var decrypted: String?
    @State private var statusMessage = "Ready"
    @State private var isWorking = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Lock icon
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.cyan)
                            .padding(.top, 16)

                        Text(statusMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        // Plaintext input
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Message")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Enter message to encrypt…", text: $plaintext, axis: .vertical)
                                .textFieldStyle(.plain)
                                .padding()
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                .lineLimit(4, reservesSpace: true)
                        }
                        .padding(.horizontal)

                        // Action buttons
                        VStack(spacing: 12) {
                            Button {
                                Task { await enroll() }
                            } label: {
                                Label("Enroll (Save Helper String)", systemImage: "key.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.indigo)
                            .disabled(isWorking)

                            HStack(spacing: 12) {
                                Button {
                                    Task { await encryptMessage() }
                                } label: {
                                    Label("Encrypt", systemImage: "lock.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.cyan)
                                .disabled(isWorking || plaintext.isEmpty)

                                Button {
                                    Task { await decryptMessage() }
                                } label: {
                                    Label("Decrypt", systemImage: "lock.open.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(.cyan)
                                .disabled(isWorking || ciphertext == nil)
                            }
                        }
                        .padding(.horizontal)

                        // Output
                        if let ct = ciphertext {
                            resultCard(title: "Ciphertext (hex)", value: ct.prefix(32).map { String(format: "%02x", $0) }.joined() + "…")
                        }

                        if let pt = decrypted {
                            resultCard(title: "Decrypted", value: pt)
                        }

                        Spacer(minLength: 32)
                    }
                }
            }
            .navigationTitle("Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .overlay {
                if isWorking {
                    ProgressView()
                        .tint(.cyan)
                        .scaleEffect(1.5)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func resultCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Actions

    private func enroll() async {
        isWorking = true
        statusMessage = "Enrolling…"
        do {
            let (_, helperString) = try buildKeyMaterial()
            try await vault.storeHelperString(helperString)
            statusMessage = "Enrolled ✓ — helper string saved in Vault."
        } catch {
            showErrorAlert(error)
        }
        isWorking = false
    }

    private func encryptMessage() async {
        isWorking = true
        statusMessage = "Encrypting…"
        do {
            let (key, _) = try buildKeyMaterial()
            let data = Data(plaintext.utf8)
            ciphertext = try vault.encrypt(plaintext: data, key: key)
            decrypted = nil
            statusMessage = "Encrypted ✓"
        } catch {
            showErrorAlert(error)
        }
        isWorking = false
    }

    private func decryptMessage() async {
        guard let ct = ciphertext else { return }
        isWorking = true
        statusMessage = "Reconstructing key…"
        do {
            let helperString = try await vault.loadHelperString()
            let seed = buildNoisySeed()
            let key = try FuzzyExtractor.reconstruct(noisySeedData: seed, helperString: helperString)
            let plainData = try vault.decrypt(ciphertext: ct, key: key)
            decrypted = String(data: plainData, encoding: .utf8) ?? "(binary data)"
            statusMessage = "Decrypted ✓"
        } catch {
            showErrorAlert(error)
        }
        isWorking = false
    }

    // MARK: - Key material builders

    /// Build seed from captured LiDAR + magnetic data (enroll path — uses best current readings).
    private func buildKeyMaterial() throws -> (key: SymmetricKey, helperString: FuzzyExtractor.HelperString) {
        // Use a synthetic point cloud and magnetic sig if sensors have not been triggered
        // (full sensor integration wired in TotemView / AnchorView).
        let cloud = lidar.capturedCloud ?? syntheticCloud()
        let mag = magnetic.currentSignature ?? syntheticMagneticSignature()
        let seed = FuzzyExtractor.buildSeed(cloud: cloud, magnetic: mag)
        return try FuzzyExtractor.enroll(seedData: seed)
    }

    private func buildNoisySeed() -> Data {
        let cloud = lidar.capturedCloud ?? syntheticCloud()
        let mag = magnetic.currentSignature ?? syntheticMagneticSignature()
        return FuzzyExtractor.buildSeed(cloud: cloud, magnetic: mag)
    }

    // MARK: - Synthetic fallbacks (used when sensors not yet scanned)

    private func syntheticCloud() -> PointCloud {
        // Reproducible deterministic cloud based on device ID.
        let id = UIDevice.current.identifierForVendor?.uuidString ?? "totem"
        var verts: [SIMD3<Float>] = []
        for (i, byte) in id.utf8.enumerated() {
            let f = Float(byte) / 255.0
            verts.append(SIMD3<Float>(f, Float(i) * 0.01, 1 - f))
        }
        return PointCloud(vertices: verts)
    }

    private func syntheticMagneticSignature() -> MagneticSignature {
        // Fixed vector — real value comes from MagneticService in AnchorView.
        struct FakeField: Decodable {}
        // Build via manual init with a stable value.
        return MagneticSignature(field: .init(x: 22.5, y: -14.3, z: 41.8))
    }

    private func showErrorAlert(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
        statusMessage = "Error"
    }
}

#Preview {
    VaultView()
}
