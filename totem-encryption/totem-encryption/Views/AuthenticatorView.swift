//
//  AuthenticatorView.swift
//  totem-encryption
//
//  Flow:
//  1. QR code on website encodes a totem:// URL.
//  2. User scans it (camera or paste). App receives the challenge.
//  3. Approval sheet opens → user scans their totem object with LiDAR right there.
//  4. Tap Approve → key reconstructed → nonce signed → access granted.

import SwiftUI
import AVFoundation

// MARK: - AuthenticatorView

struct AuthenticatorView: View {

    @Binding var incomingChallenge: ChallengeSession?
    @StateObject private var auth = AuthenticatorService()

    @State private var showApproval: ChallengeSession?
    @State private var showQRScanner = false

    // Convenience init for previews / places that don't have an incoming binding
    init(incomingChallenge: Binding<ChallengeSession?> = .constant(nil)) {
        _incomingChallenge = incomingChallenge
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    Text(auth.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)

                    if auth.sessions.isEmpty {
                        emptyState
                    } else {
                        List {
                            ForEach(auth.sessions) { session in
                                ChallengeRow(session: session)
                                    .listRowBackground(Color.black)
                                    .onTapGesture {
                                        if session.status == .pending && !session.isExpired {
                                            showApproval = session
                                        }
                                    }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }

                    Spacer()

                    VStack(spacing: 12) {
                        Button { showQRScanner = true } label: {
                            Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(.cyan)

                        Button { _ = auth.generateTestChallenge() } label: {
                            Label("Generate Test Challenge", systemImage: "wand.and.stars")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).tint(.indigo)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Authenticator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            // Approval sheet
            .sheet(item: $showApproval) { session in
                ApprovalSheetView(session: session, auth: auth)
            }
            // QR scanner sheet
            .sheet(isPresented: $showQRScanner) {
                QRScannerStubView { url in
                    showQRScanner = false
                    if let session = ChallengeSession.from(url: url) {
                        auth.receive(challenge: session)
                        showApproval = session
                    }
                }
            }
            // Incoming totem:// URL from system (QR scanned outside the app)
            .onChange(of: incomingChallenge) { _, session in
                guard let session else { return }
                auth.receive(challenge: session)
                showApproval = session
                incomingChallenge = nil
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "qrcode")
                .font(.system(size: 64)).foregroundStyle(.secondary)
            Text("No pending challenges").font(.headline).foregroundStyle(.secondary)
            Text("Tap \"Scan QR Code\" to scan a challenge from a website,\nor \"Generate Test Challenge\" to try it locally.")
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
        }
    }
}

// MARK: - Challenge Row

struct ChallengeRow: View {
    let session: ChallengeSession
    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(statusColor).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.origin).font(.headline).foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(session.status.rawValue.capitalized).font(.caption).foregroundStyle(statusColor)
                    if session.status == .pending && !session.isExpired {
                        Text("· \(session.secondsRemaining)s remaining").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if session.status == .pending && !session.isExpired {
                Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption)
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

// MARK: - Approval Sheet (with embedded LiDAR scan)

struct ApprovalSheetView: View {
    let session: ChallengeSession
    @ObservedObject var auth: AuthenticatorService
    @Environment(\.dismiss) private var dismiss

    // LiDAR lives here — user scans their object inside this sheet
    @StateObject private var lidar = LiDARService()
    @StateObject private var magnetic = MagneticService()

    @State private var step: ApprovalStep = .scan
    @State private var isProcessing = false

    enum ApprovalStep { case scan, confirm }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 48)).foregroundStyle(.cyan)
                        Text(session.origin).font(.title2.bold())
                        Text("is requesting authentication")
                            .font(.callout).foregroundStyle(.secondary)
                        Text("Nonce: \(session.nonce.prefix(8).map { String(format: "%02x", $0) }.joined())…")
                            .font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
                    }

                    CountdownView(expiresAt: session.expiresAt)

                    Divider().background(.gray)

                    // Step-dependent content
                    if step == .scan {
                        scanStep
                    } else {
                        confirmStep
                    }

                    Spacer()
                }
                .padding(.top, 24)
            }
            .navigationTitle("Approve Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.cyan)
                }
            }
            .onAppear {
                lidar.start()
                magnetic.start()
            }
            .onDisappear {
                lidar.stop()
                magnetic.stop()
            }
        }
    }

    // MARK: Step 1 — LiDAR Scan

    private var scanStep: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 40))
                    .foregroundStyle(.cyan)
                    .symbolEffect(.pulse, isActive: lidar.isRunning)
                Text("Step 1: Scan your Totem object")
                    .font(.headline)
                Text(lidar.statusMessage)
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
            }

            if let cloud = lidar.capturedCloud {
                HStack(spacing: 20) {
                    VStack {
                        Text("\(cloud.vertices.count)")
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                        Text("vertices").font(.caption2).foregroundStyle(.secondary)
                    }
                    VStack {
                        Text(magnetic.isMatch ? "✓" : "~")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(magnetic.isMatch ? .green : .orange)
                        Text("anchor").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }

            HStack(spacing: 12) {
                Button {
                    if lidar.isRunning { lidar.stop() } else { lidar.start() }
                } label: {
                    Label(lidar.isRunning ? "Stop" : "Start", systemImage: lidar.isRunning ? "stop.circle" : "play.circle")
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
            .padding(.horizontal)

            Button {
                guard lidar.capturedCloud != nil else { return }
                step = .confirm
            } label: {
                Label("Continue →", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.indigo)
            .disabled(lidar.capturedCloud == nil)
            .padding(.horizontal)
        }
    }

    // MARK: Step 2 — Approve / Deny

    private var confirmStep: some View {
        VStack(spacing: 14) {
            Label("Object scanned ✓  — Ready to approve", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green).font(.callout)

            if let cloud = lidar.capturedCloud {
                Text("\(cloud.vertices.count) vertices captured")
                    .font(.caption).foregroundStyle(.secondary)
            }

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
                Label(isProcessing ? "Approving…" : "Approve — Grant Access",
                      systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.green)
            .disabled(isProcessing)
            .padding(.horizontal)

            Button(role: .destructive) {
                auth.deny(challengeID: session.id)
                dismiss()
            } label: {
                Label("Deny", systemImage: "xmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).tint(.red)
            .disabled(isProcessing)
            .padding(.horizontal)

            Button { step = .scan } label: {
                Label("Re-scan object", systemImage: "arrow.counterclockwise")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
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
            Circle().stroke(Color.gray.opacity(0.3), lineWidth: 4).frame(width: 72, height: 72)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(secondsLeft > 10 ? Color.cyan : Color.red,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 72, height: 72)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: secondsLeft)
            Text("\(secondsLeft)s")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(secondsLeft > 10 ? .primary : .red)
        }
        .onReceive(timer) { _ in secondsLeft = max(0, Int(expiresAt.timeIntervalSinceNow)) }
        .onAppear      { secondsLeft = max(0, Int(expiresAt.timeIntervalSinceNow)) }
    }

    private var progress: CGFloat { CGFloat(secondsLeft) / 30.0 }
}

// MARK: - QR Scanner (real device) / Simulator fallback

struct QRScannerStubView: View {
    let onScan: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if targetEnvironment(simulator)
        SimulatorQRFallbackView(onScan: onScan)
        #else
        LiveQRScannerView(onScan: onScan).ignoresSafeArea()
        #endif
    }
}

struct LiveQRScannerView: UIViewControllerRepresentable {
    let onScan: (URL) -> Void
    func makeUIViewController(context: Context) -> QRScannerViewController {
        let vc = QRScannerViewController(); vc.onScan = onScan; return vc
    }
    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((URL) -> Void)?
    private var captureSession: AVCaptureSession?

    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        setupSession(); addOverlay()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async { self.captureSession?.startRunning() }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated); captureSession?.stopRunning()
    }
    private func setupSession() {
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { showError("Camera unavailable."); return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.layer.bounds; preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        captureSession = session
    }
    private func addOverlay() {
        let overlay = UIView(frame: view.bounds)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(overlay)
        let size: CGFloat = 240
        let box = UIView(frame: CGRect(x: (view.bounds.width-size)/2, y: (view.bounds.height-size)/2, width: size, height: size))
        box.layer.borderColor = UIColor.cyan.cgColor; box.layer.borderWidth = 2
        box.layer.cornerRadius = 12; box.backgroundColor = .clear
        overlay.addSubview(box)
        let path = UIBezierPath(rect: overlay.bounds)
        path.append(UIBezierPath(roundedRect: box.frame, cornerRadius: 12).reversing())
        let mask = CAShapeLayer(); mask.path = path.cgPath; overlay.layer.mask = mask
        let label = UILabel()
        label.text = "Point camera at\na Totem QR code"
        label.textColor = .white; label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textAlignment = .center; label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: box.bottomAnchor, constant: 24)
        ])
        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal); cancel.setTitleColor(.cyan, for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
        view.addSubview(cancel)
        NSLayoutConstraint.activate([
            cancel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])
    }
    @objc private func dismissSelf() { dismiss(animated: true) }
    private func showError(_ msg: String) {
        let label = UILabel(); label.text = msg; label.textColor = .red
        label.textAlignment = .center; label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let str = obj.stringValue, let url = URL(string: str) else { return }
        captureSession?.stopRunning()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss(animated: true) { self.onScan(url) }
    }
}

struct SimulatorQRFallbackView: View {
    let onScan: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "qrcode.viewfinder").font(.system(size: 72)).foregroundStyle(.cyan)
                    Text("QR Scanner").font(.title2.bold())
                    Text("Camera not available in Simulator.\nPaste a totem:// URL to test the full flow.")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal)
                    TextField("totem://challenge?id=…", text: $urlText)
                        .textFieldStyle(.plain).padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Button("Submit") { if let url = URL(string: urlText) { onScan(url) } }
                        .buttonStyle(.borderedProminent).tint(.cyan).disabled(urlText.isEmpty)
                    Spacer()
                }
                .padding(.top, 40)
            }
            .navigationTitle("Scan QR").navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(.cyan) } }
        }
    }
}

#Preview { AuthenticatorView() }
