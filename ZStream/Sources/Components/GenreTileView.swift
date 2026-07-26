//
//  GenreTileView.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/18/26.
//

import SwiftUI

struct GenreTileView: View {
    let tile: GenreTile

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: tile.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)

            Image(tile.imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
                .saturation(0)
                .contrast(1.05)
                .brightness(-0.1)
                .blendMode(.screen)
                .opacity(0.6)

            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)

            Text(tile.name)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .padding(16)
        }
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
