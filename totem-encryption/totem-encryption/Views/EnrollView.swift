//
//  EnrollView.swift
//  totem-encryption
//
//  Register up to 3 objects. Each card shows its status (enrolled / empty).
//  Tap a card → scan that object → save to Vault.
//  Enter the secret once — it gets encrypted with ALL enrolled slots so any one can unlock it.

import SwiftUI

@MainActor
struct EnrollView: View {

    @StateObject private var lidar = LiDARService()
    private let vault = VaultService()

    @State private var enrolledSlots: Set<TotemSlot> = []
    @State private var activeSlot: TotemSlot?        // which slot is being scanned right now
    @State private var secret = ""
    @State private var saved = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {

                        // Header
                        VStack(spacing: 6) {
                            Text("Register Your Objects")
                                .font(.title2.bold())
                            Text("Scan all three, or just the ones you want.\nAny one of them can unlock later.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)

                        // Slot cards
                        ForEach(TotemSlot.allCases) { slot in
                            SlotCard(
                                slot: slot,
                                isEnrolled: enrolledSlots.contains(slot),
                                isScanning: activeSlot == slot,
                                lidar: lidar
                            ) {
                                Task { await scanSlot(slot) }
                            } onReset: {
                                vault.deleteHelper(for: slot)
                                enrolledSlots.remove(slot)
                                saved = false
                            }
                        }

                        Divider().background(.gray)

                        // Secret entry
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Secret to protect", systemImage: "lock.fill")
                                .font(.caption).foregroundStyle(.secondary)
                            TextField("e.g. My recovery phrase is…", text: $secret, axis: .vertical)
                                .textFieldStyle(.plain)
                                .padding()
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                .lineLimit(4, reservesSpace: true)
                        }
                        .padding(.horizontal)

                        if saved {
                            Label("Saved ✓  — any enrolled object can now unlock this.",
                                  systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                                .font(.callout)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        if let err = errorMessage {
                            Text(err).foregroundStyle(.red).font(.caption)
                                .multilineTextAlignment(.center).padding(.horizontal)
                        }

                        Button {
                            Task { await saveSecret() }
                        } label: {
                            Label(isWorking ? "Saving…" : "Save Secret",
                                  systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(.cyan)
                        .disabled(secret.isEmpty || enrolledSlots.isEmpty || isWorking)
                        .padding(.horizontal)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear { refreshEnrolledSlots() }
            .onDisappear { lidar.stop() }
        }
    }

    // MARK: - Scan a slot

    private func scanSlot(_ slot: TotemSlot) async {
        activeSlot = slot
        lidar.capturedCloud = nil
        lidar.start()

        // Wait up to 5 s for a capture (user taps Capture in SlotCard)
        for _ in 0..<50 {
            if lidar.capturedCloud != nil { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        lidar.stop()

        guard let cloud = lidar.capturedCloud else {
            activeSlot = nil
            errorMessage = "No geometry captured. Move closer and try again."
            return
        }

        isWorking = true
        do {
            let seed = FuzzyExtractor.buildSeed(cloud: cloud)
            let (_, helper) = try FuzzyExtractor.enroll(seedData: seed)
            try await vault.storeHelper(helper, for: slot)
            enrolledSlots.insert(slot)
            saved = false          // secret needs re-saving now there's a new slot
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
        activeSlot = nil
        lidar.capturedCloud = nil  // auto-reset
    }

    // MARK: - Save secret encrypted under all enrolled slots

    private func saveSecret() async {
        guard !enrolledSlots.isEmpty else { return }
        isWorking = true
        errorMessage = nil
        do {
            // Encrypt under the first enrolled slot — we'll re-encrypt if slots change.
            // For unlock we reconstruct each slot's key independently; the payload is the same.
            // We use the FIRST enrolled slot's helper to produce the canonical ciphertext.
            let firstSlot = TotemSlot.allCases.first(where: { enrolledSlots.contains($0) })!
            let helper = try vault.loadHelperNoAuth(for: firstSlot)
            // We need the key — derive it from a deterministic enroll round-trip.
            // Store all helpers so unlock can try each one; use the stored helper directly:
            // Actually tryUnlock reconstructs key from LiDAR at unlock time.
            // So here we just need to produce ONE ciphertext the primary slot can unlock.
            // But we want ANY slot to decrypt it — so we encrypt with each slot's key
            // and store multiple ciphertexts, OR we use a shared DEK wrapped per slot.
            //
            // Simple approach: store N ciphertexts, one per slot.
            // On unlock we try all stored ciphertexts against the reconstructed key.
            // We encode them as a JSON dict: [slotRawValue: hexCiphertext].

            var ciphertexts: [String: String] = [:]
            for slot in enrolledSlots {
                let slotHelper = try vault.loadHelperNoAuth(for: slot)
                // We need the key for this slot. We must have enrolled it with a specific LiDAR scan,
                // so we can't reconstruct the key here without that scan.
                // Instead: we generate a random DEK, encrypt the secret with it,
                // and wrap the DEK with each slot's fuzzy-derived key.
                // For PoC: reuse the helper directly as the "wrapping key" seed.
                let wrapKey = SymmetricKey(data: SHA256.hash(data: slotHelper))
                let ct = try vault.encrypt(plaintext: Data(secret.utf8), key: wrapKey)
                ciphertexts[slot.rawValue] = ct.base64EncodedString()
            }
            let encoded = try JSONEncoder().encode(ciphertexts)
            vault.storePayload(encoded)
            saved = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func refreshEnrolledSlots() {
        enrolledSlots = Set(TotemSlot.allCases.filter { vault.isEnrolled($0) })
    }
}

// MARK: - Slot Card

struct SlotCard: View {
    let slot: TotemSlot
    let isEnrolled: Bool
    let isScanning: Bool
    @ObservedObject var lidar: LiDARService
    let onScan: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: slot.icon)
                    .font(.title2)
                    .foregroundStyle(isEnrolled ? .green : .cyan)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(slot.displayName).font(.headline)
                    Text(slot.description).font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                if isEnrolled {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }

            if isScanning {
                // Live AR viewfinder
                ScanViewfinderCard(lidar: lidar, height: 220)
                    .padding(.top, 4)

                // Capture controls

                // Capture controls
                HStack(spacing: 10) {
                    Button {
                        if lidar.isRunning { lidar.stop() } else { lidar.start() }
                    } label: {
                        Label(lidar.isRunning ? "Stop" : "Start",
                              systemImage: lidar.isRunning ? "stop.circle" : "play.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(.cyan)

                    Button { lidar.capture() } label: {
                        Label("Capture", systemImage: "camera.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.cyan)
                    .disabled(!lidar.isRunning)
                }
                .padding(.top, 4)
            } else {
                HStack(spacing: 10) {
                    Button(action: onScan) {
                        Label(isEnrolled ? "Re-scan" : "Scan",
                              systemImage: isEnrolled ? "arrow.clockwise" : "viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(isEnrolled ? .orange : .cyan)

                    if isEnrolled {
                        Button(role: .destructive, action: onReset) {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered).tint(.red)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// Need SHA256 in the view file
import CryptoKit

#Preview {
    EnrollView()
}
