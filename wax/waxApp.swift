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
    @StateObject private var store: CollectionStore

    init() {
        let container = AppContainer.live()
        self.container = container
        _store = StateObject(wrappedValue: container.makeCollectionStore())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .preferredColorScheme(.dark)
        }
    }
}
