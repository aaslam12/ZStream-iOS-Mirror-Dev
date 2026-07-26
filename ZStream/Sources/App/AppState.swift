//
//  AppState.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import Foundation

// UI/Navigation State, resets on every lunch
@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .home
}
