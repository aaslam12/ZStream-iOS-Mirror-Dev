//
//  TabBarVisibility.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import SwiftUI

struct TabBarHiddenPreferenceKey: PreferenceKey {
    static let defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

extension View {
    func hideTabBar(_ hidden: Bool = true) -> some View {
        preference(key: TabBarHiddenPreferenceKey.self, value: hidden)
    }
}
