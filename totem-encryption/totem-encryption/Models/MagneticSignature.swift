//
//  MagneticSignature.swift
//  totem-encryption
//
//  Created by Charles Love on 4/20/26.
//

import Foundation
import CoreMotion

/// A snapshot of the 3-axis magnetic field vector (in µT).
struct MagneticSignature: Codable {
    let x: Double
    let y: Double
    let z: Double

    init(field: CMMagneticField) {
        x = field.x
        y = field.y
        z = field.z
    }

    /// Magnitude of the vector.
    var magnitude: Double {
        (x * x + y * y + z * z).squareRoot()
    }

    /// Returns `true` when all three axes are within `tolerance` (0–1 fraction) of `baseline`.
    func matches(_ baseline: MagneticSignature, tolerance: Double = 0.05) -> Bool {
        let dx = abs(x - baseline.x) / (abs(baseline.x) + 1e-9)
        let dy = abs(y - baseline.y) / (abs(baseline.y) + 1e-9)
        let dz = abs(z - baseline.z) / (abs(baseline.z) + 1e-9)
        return dx <= tolerance && dy <= tolerance && dz <= tolerance
    }

    /// Serialise to 24 bytes (3 × Double) for use in key derivation.
    func bytes() -> Data {
        var vals = [x, y, z]
        return Data(bytes: &vals, count: vals.count * MemoryLayout<Double>.size)
    }
}
