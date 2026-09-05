//
//  CastButton.swift
//  Yoto
//
//  Created by user on 05/09/2026.
//

import SwiftUI

#if canImport(GoogleCast)
import GoogleCast

/// Google's own Cast button: shows the standard "available/connecting/connected" icon
/// states and opens the system device-picker sheet when tapped.
struct CastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> GCKUICastButton {
        GCKUICastButton(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
    }

    func updateUIView(_ uiView: GCKUICastButton, context: Context) {}
}
#else
/// GoogleCast package not added to the project yet — degrade to a disabled placeholder
/// rather than failing the build.
struct CastButton: View {
    var body: some View {
        Image(systemName: "tv.badge.wifi")
            .foregroundStyle(.secondary.opacity(0.4))
    }
}
#endif
