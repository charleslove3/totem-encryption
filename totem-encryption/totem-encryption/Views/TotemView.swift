//
//  TotemView.swift
//  totem-encryption
//
//  Created by Charles Love on 4/20/26.
//
//  Phase 1 UI — LiDAR scanner with live point count and capture button.

import SwiftUI
import ARKit

struct TotemView: View {

    @StateObject private var lidar = LiDARService()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Status card
                    VStack(spacing: 8) {
                        Image(systemName: "cube.transparent.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.cyan)
                            .symbolEffect(.pulse, isActive: lidar.isRunning)

                        Text(lidar.statusMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // Vertex count
                    if let cloud = lidar.capturedCloud {
                        VStack(spacing: 4) {
                            Text("\(cloud.vertices.count)")
                                .font(.system(size: 48, weight: .bold, design: .monospaced))
                                .foregroundStyle(.cyan)
                            Text("vertices captured")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("Centroid: \(cloud.centroid.x, specifier: "%.3f"), \(cloud.centroid.y, specifier: "%.3f"), \(cloud.centroid.z, specifier: "%.3f")")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 4)
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }

                    Spacer()

                    // Controls
                    HStack(spacing: 16) {
                        Button {
                            if lidar.isRunning { lidar.stop() } else { lidar.start() }
                        } label: {
                            Label(lidar.isRunning ? "Stop" : "Start", systemImage: lidar.isRunning ? "stop.circle" : "play.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.cyan)

                        Button {
                            lidar.capture()
                        } label: {
                            Label("Capture", systemImage: "camera.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .disabled(!lidar.isRunning)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
                .padding(.top, 48)
            }
            .navigationTitle("Totem Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

#Preview {
    TotemView()
}
