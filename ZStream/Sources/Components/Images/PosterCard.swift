//
//  PosterCard.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import SwiftUI

struct PosterCard: View {
    let item: any MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FadeInImage(url: item.posterURL)
                .frame(width: 120, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(item.displayTitle)
                .font(.subheadline)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)
                .bold()
            
            Text(subtitle)
                .font(.caption)
                .lineLimit(1)
                .foregroundColor(.gray)
                .frame(width: 120, alignment: .leading)
        }
    }
    
    private var subtitle: String {
        if let year = item.releaseYear {
            return "\(item.mediaType.text) • \(year)"
        } else {
            return item.mediaType.text
        }
    }
}
