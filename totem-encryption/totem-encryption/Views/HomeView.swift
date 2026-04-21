//
//  HomeView.swift
//  totem-encryption
//
//  Created by Charles Love on 4/20/26.
//

import SwiftUI

struct HomeView: View {
    var body: some View {
        TabView {
            TotemView()
                .tabItem {
                    Label("Totem", systemImage: "cube.transparent")
                }

            AnchorView()
                .tabItem {
                    Label("Anchor", systemImage: "location.north.line")
                }

            VaultView()
                .tabItem {
                    Label("Vault", systemImage: "lock.shield")
                }

            AuthenticatorView()
                .tabItem {
                    Label("Authenticator", systemImage: "person.badge.key")
                }
        }
        .tint(.cyan)
    }
}

#Preview {
    HomeView()
}
