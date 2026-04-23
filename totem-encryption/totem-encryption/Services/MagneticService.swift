//
//  MagneticService.swift
//  totem-encryption
//
//  Created by Charles Love on 4/20/26.
//
//  Phase 2 — Magnetic Fingerprinting
//  Streams CMMagnetometerData, computes a MagneticSignature, and validates
//  against a stored baseline within a configurable tolerance.

import CoreMotion
import Combine
import Foundation

@MainActor
final class MagneticService: ObservableObject {

    // MARK: - Published State
    @Published var currentSignature: MagneticSignature?
    @Published var baseline: MagneticSignature?
    @Published var isMatch: Bool = false
    @Published var statusMessage = "Ready"

    // MARK: - Private
    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()
    private let tolerance: Double = 0.05   // 5 %

    // MARK: - Init
    init() {
        queue.name = "com.totem.magnetic"
        queue.maxConcurrentOperationCount = 1
    }

    // MARK: - Public API

    func start() {
        guard motionManager.isMagnetometerAvailable else {
            statusMessage = "Magnetometer not available."
            return
        }
        motionManager.magnetometerUpdateInterval = 0.1
        motionManager.startMagnetometerUpdates(to: queue) { [weak self] data, error in
            guard let self, let data else { return }
            Task { @MainActor in self.handle(data) }
        }
        statusMessage = "Streaming magnetic data…"
    }

    func stop() {
        motionManager.stopMagnetometerUpdates()
        statusMessage = "Stopped"
    }

    /// Save the current reading as the reference baseline for this location.
    func saveBaseline() {
        guard let sig = currentSignature else {
            statusMessage = "No reading yet."
            return
        }
        baseline = sig
        // Persist to UserDefaults (lightweight; the Vault stores the crypto helper string).
        if let encoded = try? JSONEncoder().encode(sig) {
            UserDefaults.standard.set(encoded, forKey: "magnetic_baseline")
        }
        statusMessage = "Baseline saved (|B| = \(String(format: "%.2f", sig.magnitude)) µT)."
    }

    func loadBaseline() {
        guard let data = UserDefaults.standard.data(forKey: "magnetic_baseline"),
              let sig = try? JSONDecoder().decode(MagneticSignature.self, from: data) else { return }
        baseline = sig
    }

    // MARK: - Private

    private func handle(_ data: CMMagnetometerData) {
        let sig = MagneticSignature(field: data.magneticField)
        currentSignature = sig
        if let base = baseline {
            isMatch = sig.matches(base, tolerance: tolerance)
        }
    }
}
