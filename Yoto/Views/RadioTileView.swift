//
//  RadioTileView.swift
//  Yoto
//
//  Created by user on 05/09/2026.
//

import SwiftUI

struct RadioTileView: View {
    let station: RadioStation
    let isActive: Bool

    private static let palette: [Color] = [.pink, .orange, .yellow, .green, .teal, .blue, .indigo, .red]

    private var accentColor: Color {
        Self.palette[abs(station.id.hashValue) % Self.palette.count]
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accentColor.gradient)

                if let iconURL = station.iconURL {
                    AsyncImage(url: iconURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFit().padding(12)
                        } else {
                            fallbackIcon
                        }
                    }
                } else {
                    fallbackIcon
                }

                if isActive {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "waveform")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(.black.opacity(0.35), in: Circle())
                                .padding(5)
                        }
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)

            Text(station.title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(station.title)
        .accessibilityAddTraits(.isButton)
    }

    private var fallbackIcon: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.white)
            .padding(18)
    }
}
