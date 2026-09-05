//
//  AirPlayButton.swift
//  Yoto
//
//  Created by user on 05/09/2026.
//

import AVKit
import SwiftUI

/// Standard system AirPlay route picker. Route switching/volume for AirPlay and local
/// playback is handled entirely by the system — we just need to expose the picker.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
