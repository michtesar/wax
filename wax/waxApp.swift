//
//  waxApp.swift
//  wax
//
//  Created by Michael Tesař on 23.03.2026.
//

import SwiftUI

@main
struct waxApp: App {
    private let container: AppContainer
    @StateObject private var authStore: DiscogsAuthStore
    @StateObject private var store: CollectionStore

    init() {
        let container = AppContainer.live()
        let stores = container.makeStores()
        self.container = container
        _authStore = StateObject(wrappedValue: stores.authStore)
        _store = StateObject(wrappedValue: stores.collectionStore)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, authStore: authStore)
                .preferredColorScheme(.dark)
        }
    }
}
