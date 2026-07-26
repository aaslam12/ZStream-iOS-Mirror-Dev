//
//  Helpers.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import Foundation
import SwiftUI

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

enum ReleaseDateHelper {
    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func isFutureRelease(_ isoDateString: String?) -> Bool {
        guard let isoDateString, let date = isoDateFormatter.date(from: isoDateString) else { return false }
        return date > Date()
    }
}
