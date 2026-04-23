//
//  ARViewfinder.swift
//  totem-encryption
//
//  A live AR camera preview using ARSCNView.
//  Embed this anywhere you need to show the user what LiDAR is seeing.

import SwiftUI
import ARKit
import SceneKit

/// UIViewRepresentable wrapper around ARSCNView for a live camera feed.
struct ARViewfinder: UIViewRepresentable {

    @ObservedObject var lidar: LiDARService

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.automaticallyUpdatesLighting = true
        view.autoenablesDefaultLighting = true
        view.showsStatistics = false

        // Mesh overlay so you can see the depth reconstruction
        view.debugOptions = [.showFeaturePoints]

        // Start the session if not already running
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            let config = ARWorldTrackingConfiguration()
            config.sceneReconstruction = .meshWithClassification
            config.environmentTexturing = .none
            view.session = lidar.arSession
            view.session.run(config, options: [])
        }

        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

/// Compact viewfinder card — shows camera feed + vertex count overlay.
struct ScanViewfinderCard: View {

    @ObservedObject var lidar: LiDARService
    var height: CGFloat = 260

    var body: some View {
        ZStack(alignment: .bottom) {
            // Live camera feed
            ARViewfinder(lidar: lidar)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            // Crosshair
            crosshair

            // Bottom overlay: status + vertex count
            HStack {
                Label(lidar.statusMessage, systemImage: "camera.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                Spacer()
                if let cloud = lidar.capturedCloud {
                    Text("\(cloud.vertices.count) pts")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.cyan)
                }
            }
            .padding(10)
            .background(.black.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 0))
            .clipShape(
                .rect(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 16,
                    bottomTrailingRadius: 16,
                    topTrailingRadius: 0
                )
            )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(lidar.capturedCloud != nil ? Color.green : Color.cyan, lineWidth: 2)
        )
    }

    private var crosshair: some View {
        ZStack {
            // Target box in the center
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.cyan.opacity(0.8), lineWidth: 1.5)
                .frame(width: 100, height: 100)

            // Corner ticks
            ForEach(0..<4, id: \.self) { i in
                let angle = Double(i) * 90.0
                Rectangle()
                    .fill(Color.cyan)
                    .frame(width: 16, height: 2)
                    .offset(x: i < 2 ? -49 : 49)
                    .rotationEffect(.degrees(angle))
            }
        }
    }
}
