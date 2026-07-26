//
//  AppTab.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case downloads
    case profile
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
            case .home: return "Home"
            case .downloads: return "Downloads"
            case .profile: return "Profile"
            case .search: return "Search"
        }
    }

    var icon: String {
        switch self {
            case .home: return "house"
            case .downloads: return "square.and.arrow.down"
            case .profile: return "person"
            case .search: return "magnifyingglass"
        }
    }
}
