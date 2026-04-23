//
//  UnlockView.swift
//  totem-encryption
//
//  Scan ANY ONE of your registered objects to unlock.
//  Auto-resets after each successful or failed scan.
//  After a successful unlock, offers to re-enroll other slots.

import SwiftUI
import CryptoKit

@MainActor
struct UnlockView: View {

    @StateObject private var lidar = LiDARService()
    private let vault = VaultService()

    enum UnlockState {
        case idle, scanning, trying, success(slot: TotemSlot, secret: String), failed
    }

    @State private var state: UnlockState = .idle
    @State private var errorMessage: String?
    @State private var showReenroll = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    // Big status icon
                    statusIcon

                    // State-specific content
                    switch state {
                    case .idle:          idleContent
                    case .scanning:      scanningContent
                    case .trying:        tryingContent
                    case .success(let slot, let secret): successContent(slot: slot, secret: secret)
                    case .failed:        failedContent
                    }

                    Spacer()
                }
                .padding(.horizontal)
            }
            .navigationTitle("Unlock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    enrolledBadge
                }
            }
            .onDisappear { lidar.stop() }
            .sheet(isPresented: $showReenroll) {
                EnrollView()
            }
        }
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        switch state {
        case .idle:
            Image(systemName: "lock.fill")
                .font(.system(size: 64)).foregroundStyle(.cyan)
        case .scanning:
            Image(systemName: "cube.transparent")
                .font(.system(size: 64)).foregroundStyle(.cyan)
                .symbolEffect(.pulse)
        case .trying:
            ProgressView().tint(.cyan).scaleEffect(2)
        case .success:
            Image(systemName: "lock.open.fill")
                .font(.system(size: 64)).foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 64)).foregroundStyle(.red)
        }
    }

    // MARK: - Idle

    private var idleContent: some View {
        VStack(spacing: 16) {
            Text("Scan any registered object to unlock")
                .font(.headline).multilineTextAlignment(.center)

            if vault.enrolledSlots.isEmpty {
                Text("No objects registered yet.\nGo to Setup to add your objects.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Go to Setup") { showReenroll = true }
                    .buttonStyle(.borderedProminent).tint(.indigo)
            } else {
                // Show which slots are enrolled
                HStack(spacing: 16) {
                    ForEach(vault.enrolledSlots) { slot in
                        VStack(spacing: 4) {
                            Image(systemName: slot.icon).foregroundStyle(.cyan)
                            Text(slot.displayName).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                Button {
                    startScan()
                } label: {
                    Label("Start Scan", systemImage: "viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.cyan)
            }
        }
    }

    // MARK: - Scanning

    private var scanningContent: some View {
        VStack(spacing: 16) {
            Text(lidar.statusMessage)
                .font(.callout).foregroundStyle(.secondary)

            if let cloud = lidar.capturedCloud {
                Text("\(cloud.vertices.count) vertices")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.cyan)
            }

            HStack(spacing: 12) {
                Button {
                    if lidar.isRunning { lidar.stop() } else { lidar.start() }
                } label: {
                    Label(lidar.isRunning ? "Stop" : "Start",
                          systemImage: lidar.isRunning ? "stop.circle" : "play.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(.cyan)

                Button {
                    lidar.capture()
                    if lidar.capturedCloud != nil { Task { await attemptUnlock() } }
                } label: {
                    Label("Capture", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.cyan)
                .disabled(!lidar.isRunning)
            }

            Button("Cancel") { reset() }
                .foregroundStyle(.secondary).font(.caption)
        }
    }

    // MARK: - Trying

    private var tryingContent: some View {
        Text("Trying all registered objects…")
            .font(.callout).foregroundStyle(.secondary)
    }

    // MARK: - Success

    private func successContent(slot: TotemSlot, secret: String) -> some View {
        VStack(spacing: 16) {
            Label("Unlocked with \(slot.displayName)", systemImage: slot.icon)
                .font(.headline).foregroundStyle(.green)

            Text(secret)
                .font(.system(.body, design: .monospaced))
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .textSelection(.enabled)

            HStack(spacing: 12) {
                Button {
                    showReenroll = true
                } label: {
                    Label("Re-enroll Objects", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(.indigo)

                Button { reset() } label: {
                    Label("Lock", systemImage: "lock.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.cyan)
            }
        }
    }

    // MARK: - Failed

    private var failedContent: some View {
        VStack(spacing: 16) {
            Text("No match — wrong object or not enrolled")
                .font(.callout).foregroundStyle(.red)
                .multilineTextAlignment(.center)

            if let err = errorMessage {
                Text(err).font(.caption2).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            Button {
                reset()
                startScan()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.cyan)

            Button { reset() } label: {
                Text("Cancel")
            }
            .foregroundStyle(.secondary).font(.caption)
        }
    }

    // MARK: - Enrolled badge

    private var enrolledBadge: some View {
        let count = vault.enrolledSlots.count
        return Text("\(count)/3")
            .font(.caption.bold())
            .foregroundStyle(count > 0 ? .cyan : .secondary)
    }

    // MARK: - Actions

    private func startScan() {
        lidar.capturedCloud = nil
        lidar.start()
        state = .scanning
        errorMessage = nil
    }

    private func attemptUnlock() async {
        lidar.stop()
        guard let cloud = lidar.capturedCloud else {
            state = .failed
            return
        }
        state = .trying

        do {
            // Build ciphertexts dict
            guard let payloadData = vault.loadPayload(),
                  let ciphertexts = try? JSONDecoder().decode([String: String].self, from: payloadData) else {
                state = .failed
                errorMessage = "No secret saved yet. Go to Setup."
                return
            }

            try await vault.authenticateBiometric(reason: "Unlock your Totem.")

            let seed = FuzzyExtractor.buildSeed(cloud: cloud)

            for slot in TotemSlot.allCases where vault.isEnrolled(slot) {
                guard let helper = try? vault.loadHelperNoAuth(for: slot),
                      let key = try? FuzzyExtractor.reconstruct(noisySeedData: seed, helperString: helper),
                      let ctB64 = ciphertexts[slot.rawValue],
                      let ctData = Data(base64Encoded: ctB64) else { continue }

                // The wrapping key = SHA256(helper) — matches EnrollView
                let wrapKey = SymmetricKey(data: SHA256.hash(data: helper))
                if let plainData = try? vault.decrypt(ciphertext: ctData, key: wrapKey),
                   let secret = String(data: plainData, encoding: .utf8) {
                    // ✅ Match — auto-reset LiDAR
                    lidar.capturedCloud = nil
                    state = .success(slot: slot, secret: secret)
                    return
                }
            }

            lidar.capturedCloud = nil   // auto-reset on failure too
            state = .failed

        } catch {
            lidar.capturedCloud = nil
            state = .failed
            errorMessage = error.localizedDescription
        }
    }

    private func reset() {
        lidar.stop()
        lidar.capturedCloud = nil
        state = .idle
        errorMessage = nil
    }
}

#Preview {
    UnlockView()
}
