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
            UnlockView()
                .tabItem { Label("Unlock", systemImage: "lock.open.fill") }
                .tag(0)

            EnrollView()
                .tabItem { Label("Setup", systemImage: "wand.and.stars") }
                .tag(1)

            AuthenticatorView(incomingChallenge: $router.incomingChallenge)
                .tabItem { Label("Auth", systemImage: "person.badge.key") }
                .tag(2)
        }
        .tint(.cyan)
        .onChange(of: router.incomingChallenge) { _, challenge in
            if challenge != nil { selectedTab = 2 }
        }
    }
}

#Preview {
    HomeView().environmentObject(AppRouter.shared)
}
