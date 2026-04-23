//
//  LiDARService.swift
//  totem-encryption
//
//  Created by Charles Love on 4/20/26.
//
//  Phase 1 — LiDAR Geometry Engine
//  Captures raw ARMeshAnchor vertices inside a 10 cm³ bounding box,
//  normalises to centroid, sorts by radial distance (rotation-invariant),
//  and returns a PointCloud ready for hashing.

import ARKit
import Combine
import simd

@MainActor
final class LiDARService: NSObject, ObservableObject {

    // MARK: - Published State
    @Published var isRunning = false
    @Published var capturedCloud: PointCloud?
    @Published var statusMessage = "Ready"

    // MARK: - Private
    private let session = ARSession()
    private let boundingBoxHalfSize: Float = 0.05 // 10 cm → ±5 cm radius

    // MARK: - Public API

    func start() {
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) else {
            statusMessage = "LiDAR not available on this device."
            return
        }
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .meshWithClassification
        config.environmentTexturing = .none
        session.delegate = self
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
        statusMessage = "Scanning…"
    }

    func stop() {
        session.pause()
        isRunning = false
        statusMessage = "Stopped"
    }

    /// Snapshot the current mesh anchors, filter to the bounding box, and build a PointCloud.
    func capture() {
        guard let frame = session.currentFrame else {
            statusMessage = "No AR frame yet."
            return
        }

        var allVertices: [SIMD3<Float>] = []

        for anchor in frame.anchors.compactMap({ $0 as? ARMeshAnchor }) {
            let geometry = anchor.geometry

            for i in 0 ..< geometry.vertices.count {
                // Extract vertex from Metal buffer
                let vertex: SIMD3<Float> = geometry.vertices.vertex(at: UInt32(i))

                // Transform to world space
                let localPos = SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1)
                let worldPos = anchor.transform * localPos
                let world = SIMD3<Float>(worldPos.x, worldPos.y, worldPos.z)

                // Filter to bounding box around world origin (or we could use camera focus point)
                if abs(world.x) <= boundingBoxHalfSize &&
                   abs(world.y) <= boundingBoxHalfSize &&
                   abs(world.z) <= boundingBoxHalfSize {
                    allVertices.append(world)
                }
            }
        }

        guard !allVertices.isEmpty else {
            statusMessage = "No geometry in bounding box. Move closer to the object."
            return
        }

        capturedCloud = PointCloud(vertices: allVertices)
        statusMessage = "Captured \(allVertices.count) vertices."
    }
}

// MARK: - ARSessionDelegate
extension LiDARService: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in self.statusMessage = "AR Error: \(error.localizedDescription)" }
    }
}

// MARK: - ARGeometrySource Vertex Helper
private extension ARGeometrySource {
    func vertex(at index: UInt32) -> SIMD3<Float> {
        assert(componentsPerVector == 3)
        let pointer = buffer.contents().advanced(by: Int(offset) + Int(index) * Int(stride))
        return pointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
    }
}
