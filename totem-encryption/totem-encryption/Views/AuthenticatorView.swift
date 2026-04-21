//
//  AuthenticatorView.swift
//  totem-encryption
//
//  Created by Charles Love on 4/20/26.
//
//  The main authenticator tab.
//  - Shows a live list of pending / historical challenge sessions.
//  - "Generate Test Challenge" simulates a server-issued challenge so you can
//    run the full flow before connecting a real back-end.
//  - "Scan QR" stub: wired up to AVFoundation QR scanner when phone is connected.
//  - Tap a pending challenge → AuthenticatorApprovalView (scan totem → approve/deny).

import SwiftUI

struct AuthenticatorView: View {

    @StateObject private var auth = AuthenticatorService()
    @StateObject private var lidar = LiDARService()
    @StateObject private var magnetic = MagneticService()

    @State private var showApproval: ChallengeSession? = nil
    @State private var showQRScanner = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Status banner
                    Text(auth.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)

                    // Challenge list
                    if auth.sessions.isEmpty {
                        emptyState
                    } else {
                        List {
                            ForEach(auth.sessions) { session in
                                ChallengeRow(session: session)
                                    .listRowBackground(Color.black)
                                    .onTapGesture {
                                        if session.status == .pending {
                                            showApproval = session
                                        }
                                    }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }

                    Spacer()

                    // Bottom controls
                    VStack(spacing: 12) {
                        Button {
                            showQRScanner = true
                        } label: {
                            Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)

                        Button {
                            _ = auth.generateTestChallenge()
                        } label: {
                            Label("Generate Test Challenge", systemImage: "wand.and.stars")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.indigo)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Authenticator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(item: $showApproval) { session in
                AuthenticatorApprovalView(
                    session: session,
                    auth: auth,
                    lidar: lidar,
                    magnetic: magnetic
                )
            }
            .sheet(isPresented: $showQRScanner) {
                QRScannerStubView { url in
                    showQRScanner = false
                    if let session = ChallengeSession.from(url: url) {
                        auth.receive(challenge: session)
                    }
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "qrcode")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No pending challenges")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Tap \"Scan QR Code\" to scan a challenge from a website,\nor \"Generate Test Challenge\" to try it locally.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}

// MARK: - Challenge Row

struct ChallengeRow: View {
    let session: ChallengeSession

    var body: some View {
        HStack(spacing: 14) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.origin)
                    .font(.headline)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(session.status.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                    if session.status == .pending && !session.isExpired {
                        Text("· \(session.secondsRemaining)s remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if session.status == .pending && !session.isExpired {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
        }
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        switch session.status {
        case .pending:  return session.isExpired ? .gray : .cyan
        case .approved: return .green
        case .denied:   return .red
        case .expired:  return .gray
        }
    }
}

// MARK: - Approval Sheet

struct AuthenticatorApprovalView: View {
    let session: ChallengeSession
    @ObservedObject var auth: AuthenticatorService
    @ObservedObject var lidar: LiDARService
    @ObservedObject var magnetic: MagneticService

    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 28) {
                    // Origin + nonce preview
                    VStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.cyan)

                        Text(session.origin)
                            .font(.title2.bold())
                            .foregroundStyle(.primary)

                        Text("is requesting authentication")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Text("Nonce: \(session.nonce.prefix(8).map { String(format: "%02x", $0) }.joined())…")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    // Countdown
                    CountdownView(expiresAt: session.expiresAt)

                    Spacer()

                    // Instruction
                    Label("Scan your Totem object, then tap Approve.", systemImage: "cube.transparent")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    // Approve / Deny
                    VStack(spacing: 12) {
                        Button {
                            Task {
                                isProcessing = true
                                await auth.approve(
                                    challengeID: session.id,
                                    cloud: lidar.capturedCloud,
                                    magnetic: magnetic.currentSignature
                                )
                                isProcessing = false
                                dismiss()
                            }
                        } label: {
                            Label(isProcessing ? "Approving…" : "Approve", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(isProcessing)

                        Button(role: .destructive) {
                            auth.deny(challengeID: session.id)
                            dismiss()
                        } label: {
                            Label("Deny", systemImage: "xmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(isProcessing)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
                .padding(.top, 32)
            }
            .navigationTitle("Approve Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.cyan)
                }
            }
        }
    }
}

// MARK: - Countdown View

struct CountdownView: View {
    let expiresAt: Date
    @State private var secondsLeft: Int = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                .frame(width: 80, height: 80)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(secondsLeft > 10 ? Color.cyan : Color.red, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 80, height: 80)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: secondsLeft)

            Text("\(secondsLeft)s")
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(secondsLeft > 10 ? .primary : .red)
        }
        .onReceive(timer) { _ in
            secondsLeft = max(0, Int(expiresAt.timeIntervalSinceNow))
        }
        .onAppear {
            secondsLeft = max(0, Int(expiresAt.timeIntervalSinceNow))
        }
    }

    private var progress: CGFloat {
        let total = 30.0
        return CGFloat(secondsLeft) / total
    }
}

// MARK: - QR Scanner Stub
// Wired to AVFoundation when a real device is connected.
// For now shows a text field to paste a totem:// URL.

struct QRScannerStubView: View {
    let onScan: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 20) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 72))
                        .foregroundStyle(.cyan)

                    Text("QR Scanner")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)

                    Text("Camera scanner will appear here on device.\nPaste a totem:// URL below to test.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    TextField("totem://challenge?id=…", text: $urlText)
                        .textFieldStyle(.plain)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Button("Submit") {
                        if let url = URL(string: urlText) {
                            onScan(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(urlText.isEmpty)

                    Spacer()
                }
                .padding(.top, 40)
            }
            .navigationTitle("Scan QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.cyan)
                }
            }
        }
    }
}

#Preview {
    AuthenticatorView()
}
