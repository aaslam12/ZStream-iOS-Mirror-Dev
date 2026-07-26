//
//  MenuRowView.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/18/26.
//

import SwiftUI

struct MenuRow: View {
    let icon: String
    let title: String
    var badge: String? = nil
    var glowBadge: String? = nil
    var isDisabled: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .frame(width: 24)
                .foregroundStyle(isDisabled ? .secondary : .primary)

            Text(title)
                .foregroundStyle(isDisabled ? .secondary : .primary)

            Spacer()

            if let badge {
                Text(badge)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            } else if let glowBadge {
                PlainBadge(text: glowBadge)
            }
        }
        .padding(.vertical, 4)
    }
}
