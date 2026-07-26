//
//  AppLogoBadge.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import SwiftUI

struct AppLogoBadge: View {
    @State private var isPressed = false
    @State private var hasAppeared = false

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .modifier(BadgeBackground(isPressed: $isPressed))
            .scaleEffect(hasAppeared ? 1.0 : 0.6)
            .opacity(hasAppeared ? 1.0 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                    hasAppeared = true
                }
            }
    }
    
    private var content: some View {
        HStack(spacing: 8) {
            Image("Icon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .foregroundStyle(.blue)
            
            Text("Z-Stream")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
        }
    }
}

private struct BadgeBackground: ViewModifier {
    @Binding var isPressed: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .scaleEffect(isPressed ? 1.15 : 1.0)
                .onTapGesture {
                    withAnimation(.interpolatingSpring(stiffness: 300, damping: 8)) {
                        isPressed = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.interpolatingSpring(stiffness: 300, damping: 8)) {
                            isPressed = false
                        }
                    }
                }
        }
    }
}
