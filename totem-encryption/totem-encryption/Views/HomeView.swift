//
//  HomeView.swift
//  totem-encryption
//
//  Created by Charles Love on 4/20/26.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TotemView()
                .tabItem { Label("Totem", systemImage: "cube.transparent") }
                .tag(0)

            AnchorView()
                .tabItem { Label("Anchor", systemImage: "location.north.line") }
                .tag(1)

            VaultView()
                .tabItem { Label("Vault", systemImage: "lock.shield") }
                .tag(2)

            AuthenticatorView(incomingChallenge: $router.incomingChallenge)
                .tabItem { Label("Authenticator", systemImage: "person.badge.key") }
                .tag(3)

            SetupView()
                .tabItem { Label("Setup", systemImage: "wand.and.stars") }
                .tag(4)
        }
        .tint(.cyan)
        .onChange(of: router.incomingChallenge) { _, challenge in
            if challenge != nil { selectedTab = 3 }
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AppRouter.shared)
}
