//
//  PointCloud.swift
//  totem-encryption
//
//  Created by Charles Love on 4/20/26.
//

import Foundation
import simd
import Accelerate

/// A captured point cloud from ARKit, normalised and ready for hashing.
struct PointCloud {

    // MARK: - Raw Data
    let vertices: [SIMD3<Float>]

    // MARK: - Derived

    /// The arithmetic mean of all vertices.
    var centroid: SIMD3<Float> {
        guard !vertices.isEmpty else { return .zero }
        let sum = vertices.reduce(SIMD3<Float>.zero, +)
        return sum / Float(vertices.count)
    }

    /// Vertices translated so that the centroid is at the origin.
    var centred: [SIMD3<Float>] {
        let c = centroid
        return vertices.map { $0 - c }
    }

    /// Euclidean distances from the centroid, sorted ascending.
    /// Sorting by radial distance makes the sequence **rotation-invariant**.
    var sortedRadialDistances: [Float] {
        centred.map { simd_length($0) }.sorted()
    }

    // MARK: - Serialisation

    /// Serialise sorted radial distances to a raw byte buffer for hashing.
    func radialDistancesBytes() -> Data {
        var distances = sortedRadialDistances
        return Data(bytes: &distances, count: distances.count * MemoryLayout<Float>.size)
    }
}
