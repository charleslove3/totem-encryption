//
//  totem_encryptionApp.swift
//  totem-encryption
//
//  Created by Charles Love on 4/20/26.
//

import SwiftUI

/// Shared object that carries an incoming totem:// challenge URL
/// from the system into the view hierarchy.
@MainActor
final class AppRouter: ObservableObject {
    @Published var incomingChallenge: ChallengeSession?
    static let shared = AppRouter()
    private init() {}

    func handle(url: URL) {
        guard let session = ChallengeSession.from(url: url) else { return }
        incomingChallenge = session
    }
}

@main
struct totem_encryptionApp: App {
    @StateObject private var router = AppRouter.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(router)
                .onOpenURL { url in
                    router.handle(url: url)
                }
        }
    }
}
