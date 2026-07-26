//
//  GenreTile.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/18/26.
//

import Foundation
import SwiftUI

struct GenreTile: Identifiable, Hashable {
    let id: Int
    let name: String
    let imageName: String
    let gradient: [Color]

    static func == (lhs: GenreTile, rhs: GenreTile) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
