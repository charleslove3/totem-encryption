//
//  AnchorView.swift
//  totem-encryption
//
//  Created by Charles Love on 4/20/26.
//
//  Phase 2 UI — Magnetic fingerprint streaming, baseline save/load, match indicator.

import SwiftUI

struct AnchorView: View {

    @StateObject private var magnetic = MagneticService()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 28) {
                    // Icon + match indicator
                    ZStack {
                        Circle()
                            .fill(magnetic.isMatch ? Color.green.opacity(0.2) : Color.gray.opacity(0.1))
                            .frame(width: 120, height: 120)
                            .animation(.easeInOut(duration: 0.4), value: magnetic.isMatch)

                        Image(systemName: magnetic.isMatch ? "location.north.line.fill" : "location.north.line")
                            .font(.system(size: 52))
                            .foregroundStyle(magnetic.isMatch ? .green : .cyan)
                            .symbolEffect(.bounce, value: magnetic.isMatch)
                    }

                    Text(magnetic.statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    // Live readings
                    if let sig = magnetic.currentSignature {
                        VStack(spacing: 8) {
                            magneticRow("X", value: sig.x)
                            magneticRow("Y", value: sig.y)
                            magneticRow("Z", value: sig.z)
                            Divider().background(.gray)
                            magneticRow("|B|", value: sig.magnitude)
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    }

                    if magnetic.baseline != nil {
                        Label(
                            magnetic.isMatch ? "Location matched ✓" : "Location mismatch ✗",
                            systemImage: magnetic.isMatch ? "checkmark.seal.fill" : "xmark.seal.fill"
                        )
                        .foregroundStyle(magnetic.isMatch ? .green : .red)
                        .font(.headline)
                    }

                    Spacer()

                    // Controls
                    HStack(spacing: 16) {
                        Button {
                            magnetic.start()
                        } label: {
                            Label("Start", systemImage: "play.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.cyan)

                        Button {
                            magnetic.saveBaseline()
                        } label: {
                            Label("Save Baseline", systemImage: "pin.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
                .padding(.top, 48)
            }
            .navigationTitle("Magnetic Anchor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear { magnetic.loadBaseline() }
            .onDisappear { magnetic.stop() }
        }
    }

    @ViewBuilder
    private func magneticRow(_ label: String, value: Double) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)
            Spacer()
            Text(String(format: "%+.4f µT", value))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }
}

#Preview {
    AnchorView()
}
