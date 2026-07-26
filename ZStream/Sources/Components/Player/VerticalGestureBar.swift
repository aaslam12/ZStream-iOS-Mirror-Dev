//
//  VerticalGestureBar.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import SwiftUI

struct VerticalGestureBar: View {
    let icon: String
    let value: Double // 0...1

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))

            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule()
                        .fill(.white)
                        .frame(height: geo.size.height * value)
                }
            }
            .frame(width: 5)
        }
        .padding(.vertical, 14)
        .frame(width: 34, height: 150)
        .background(.black.opacity(0.55), in: Capsule())
    }
}
