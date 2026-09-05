//
//  YotoApp.swift
//  Yoto
//
//  Created by user on 05/09/2026.
//

import SwiftUI

@main
struct YotoApp: App {
    init() {
        CastManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
