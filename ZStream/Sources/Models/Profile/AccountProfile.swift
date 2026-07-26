//
//  AccountProfile.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import Foundation

struct AccountProfile: Codable, Equatable {
    var deviceName: String
    var iconName: String
    var colorOneHex: String
    var colorTwoHex: String
}
