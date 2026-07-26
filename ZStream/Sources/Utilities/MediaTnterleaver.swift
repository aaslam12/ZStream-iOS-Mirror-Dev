//
//  MediaTnterleaver.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/22/26.
//

import Foundation

func interleave(_ a: [any MediaItem], _ b: [any MediaItem]) -> [any MediaItem] {
    var result: [any MediaItem] = []
    let maxCount = max(a.count, b.count)
    for i in 0..<maxCount {
        if i < a.count { result.append(a[i]) }
        if i < b.count { result.append(b[i]) }
    }
    return result
}
