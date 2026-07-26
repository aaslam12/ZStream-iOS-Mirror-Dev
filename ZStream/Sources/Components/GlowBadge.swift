//
//  GlowBadge.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/18/26.
//

import SwiftUI

struct GlowBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(
                    LinearGradient(colors: [.purple, .cyan], startPoint: .leading, endPoint: .trailing)
                )
            )
            .shadow(color: .purple.opacity(0.7), radius: 5)
            .shadow(color: .cyan.opacity(0.4), radius: 9)
    }
}
