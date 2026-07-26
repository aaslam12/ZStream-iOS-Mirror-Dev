//
//  MainView.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import SwiftUI

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @State private var isTabBarHidden = false
    @EnvironmentObject var settings: AppSettings
    
    var body: some View {
        ZStack(alignment: .bottom) {
            currentScreen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onPreferenceChange(TabBarHiddenPreferenceKey.self) { hidden in
                    isTabBarHidden = hidden
                }
            
            if !isTabBarHidden {
                TabBar(selection: $appState.selectedTab)
            }
            
            
        }
        .tint(settings.theme.accent)
        .animation(.easeInOut(duration: 0.2), value: isTabBarHidden)
    }
    
    @ViewBuilder
    private var currentScreen: some View {
        switch appState.selectedTab {
            case .home: HomeView()
            default: Text("Coming soon")
        }
    }
}
