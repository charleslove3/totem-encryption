//
//  SetupView.swift
//  totem-encryption
//
//  Created by Charles Love on 4/20/26.
//
//  Guided 3-step onboarding that takes you from zero to a live QR you can scan:
//
//  Step 1 — Scan your objects (LiDAR) to build your physical signature.
//  Step 2 — Enter a secret message and enroll (encrypt + save helper string).
//  Step 3 — Get a QR code. Scan it with iOS camera → opens app → scan objects → access granted.

import SwiftUI

@MainActor
struct SetupView: View {

    @StateObject private var lidar    = LiDARService()

    private let vault = VaultService()

    // Wizard state
    @State private var step: SetupStep = .scanObject
    @State private var secret = ""
    @State private var ciphertext: Data?
    @State private var challenge: ChallengeSession?
    @State private var statusMessage = ""
    @State private var isWorking = false
    @State private var showError = false
    @State private var errorMessage = ""

    enum SetupStep: Int, CaseIterable {
        case scanObject = 1
        case enroll     = 2
        case qrCode     = 3

        var title: String {
            switch self {
            case .scanObject: return "Step 1 of 3 — Scan Your Totem"
            case .enroll:     return "Step 2 of 3 — Protect a Secret"
            case .qrCode:     return "Step 3 of 3 — Your Access QR Code"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.gray.opacity(0.3))
                            Rectangle()
                                .fill(Color.cyan)
                                .frame(width: geo.size.width * CGFloat(step.rawValue) / 3)
                                .animation(.spring(), value: step)
                        }
                        .frame(height: 3)
                    }
                    .frame(height: 3)

                    ScrollView {
                        VStack(spacing: 28) {
                            Text(step.title)
                                .font(.headline)
                                .foregroundStyle(.cyan)
                                .padding(.top, 20)

                            switch step {
                            case .scanObject: scanObjectStep
                            case .enroll:     enrollStep
                            case .qrCode:     qrCodeStep
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Totem Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .overlay {
                if isWorking { ProgressView().tint(.cyan).scaleEffect(1.5) }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage) }
            .onAppear {
                lidar.start()
            }
            .onDisappear {
                lidar.stop()
            }
        }
    }

    // MARK: - Step 1: LiDAR Scan

    private var scanObjectStep: some View {
        VStack(spacing: 20) {
            instructionCard(
                icon: "cube.transparent",
                text: "Hold your phone 10–20 cm above your totem object (wrist, palm, keyboard, fingernail). Tap Start, then Capture."
            )

            // Live status
            Image(systemName: "cube.transparent")
                .font(.system(size: 56))
                .foregroundStyle(.cyan)
                .symbolEffect(.pulse, isActive: lidar.isRunning)

            Text(lidar.statusMessage)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let cloud = lidar.capturedCloud {
                statsCard(vertices: cloud.vertices.count)
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

                Button { lidar.capture() } label: {
                    Label("Capture", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.cyan)
                .disabled(!lidar.isRunning)
            }

            nextButton(label: "Object scanned — Next →") {
                step = .enroll
            }
            .disabled(lidar.capturedCloud == nil)
        }
    }

    // MARK: - Step 2: Enroll (encrypt secret)

    private var enrollStep: some View {
        VStack(spacing: 20) {
            instructionCard(
                icon: "lock.shield.fill",
                text: "Enter the secret message you want to protect. Tap 'Enroll & Encrypt'. Your LiDAR scan and magnetic anchor are used to derive the key."
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Secret message")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("e.g. My Wi-Fi password is…", text: $secret, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .lineLimit(4, reservesSpace: true)
            }

            if ciphertext != nil {
                Label("Encrypted ✓ — Helper string saved to Vault", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green).font(.callout)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await enrollAndEncrypt() }
            } label: {
                Label(ciphertext == nil ? "Enroll & Encrypt" : "Re-enroll",
                      systemImage: "key.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.cyan)
            .disabled(secret.isEmpty || isWorking)

            nextButton(label: "Enrolled — Show My QR Code →") {
                generateChallenge()
                step = .qrCode
            }
            .disabled(ciphertext == nil)
        }
    }

    // MARK: - Step 3: QR Code

    private var qrCodeStep: some View {
        VStack(spacing: 20) {
            instructionCard(
                icon: "qrcode",
                text: "Point the iOS Camera (or another device) at this QR code. It will open the Totem app, ask you to scan your object, and — if it matches — grant access."
            )

            if let ch = challenge, let qrURL = ch.qrURL {
                QRDisplayView(
                    title: "demo.totem.app",
                    subtitle: "Scan with iOS Camera to authenticate",
                    content: qrURL.absoluteString,
                    size: 280
                )

                Text("Expires in \(ch.secondsRemaining > 0 ? "\(ch.secondsRemaining)s" : "—")")
                    .font(.caption).foregroundStyle(ch.secondsRemaining > 10 ? .secondary : .red)
                    .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                        // Force refresh by toggling a throwaway state
                    }
            }

            Button {
                generateChallenge()
            } label: {
                Label("Regenerate QR", systemImage: "arrow.clockwise.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).tint(.cyan)

            Button {
                step = .scanObject
                lidar.capturedCloud = nil
                ciphertext = nil
                challenge = nil
                secret = ""
            } label: {
                Label("Start Over", systemImage: "arrow.counterclockwise")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func enrollAndEncrypt() async {
        guard let cloud = lidar.capturedCloud else {
            showErr("Scan an object first.")
            return
        }
        isWorking = true
        do {
            let seed = FuzzyExtractor.buildSeed(cloud: cloud)
            let (key, helperString) = try FuzzyExtractor.enroll(seedData: seed)
            try await vault.storeHelperString(helperString)
            ciphertext = try vault.encrypt(plaintext: Data(secret.utf8), key: key)
            UserDefaults.standard.set(ciphertext, forKey: "totem_ciphertext")
        } catch {
            showErr(error.localizedDescription)
        }
        isWorking = false
    }

    private func generateChallenge() {
        challenge = ChallengeSession(origin: "demo.totem.app", ttl: 120)
    }

    private func showErr(_ msg: String) {
        errorMessage = msg; showError = true
    }

    // MARK: - Sub-views

    private func instructionCard(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(.cyan).font(.title2)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func statsCard(vertices: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(vertices)")
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan)
            Text("vertices captured")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func nextButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).tint(.indigo)
    }
}

#Preview {
    SetupView()
}
