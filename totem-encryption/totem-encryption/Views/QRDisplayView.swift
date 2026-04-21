//
//  QRDisplayView.swift
//  totem-encryption
//
//  Created by Charles Love on 4/20/26.
//
//  Generates and displays a real scannable QR code from any string
//  using CoreImage — no external dependencies.

import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - QR Image Generator

enum QRGenerator {
    /// Returns a scaled UIImage of the QR code for `string`, or nil if CIFilter fails.
    static func image(for string: String, size: CGFloat = 300) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "H"          // High error correction — survives partial occlusion

        guard let output = filter.outputImage else { return nil }

        // Scale up from the tiny CIImage (typically 33×33 px) to the requested size
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - SwiftUI wrapper

struct QRDisplayView: View {
    let title: String
    let subtitle: String
    let content: String              // The string to encode (e.g. a totem:// URL)
    var size: CGFloat = 260

    @State private var qrImage: UIImage?

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let img = qrImage {
                Image(uiImage: img)
                    .interpolation(.none)         // Keep pixels crisp (no blur)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .cyan.opacity(0.4), radius: 12)
            } else {
                ProgressView()
                    .frame(width: size, height: size)
            }

            // Show the raw URL so they can copy it if needed
            Text(content)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .padding(.horizontal)
        }
        .task {
            // Generate off the main thread
            let str = content
            let s = size * UIScreen.main.scale    // Render at display resolution
            qrImage = await Task.detached(priority: .userInitiated) {
                QRGenerator.image(for: str, size: s)
            }.value
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        QRDisplayView(
            title: "Scan to authenticate",
            subtitle: "Point this at the Totem app",
            content: "totem://challenge?id=550E8400-E29B-41D4-A716-446655440000&origin=demo.totem.app&nonce=deadbeef1234567890abcdef&ttl=30"
        )
    }
}
