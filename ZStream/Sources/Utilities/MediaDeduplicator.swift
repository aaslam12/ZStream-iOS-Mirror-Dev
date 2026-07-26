//
//  TmdbGenres.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import Foundation

struct MediaDeduplicator {
    private var seenKeys: Set<String> = []
    
    mutating func filter(_ items: [any MediaItem], minimumCount: Int = 5) -> [ any MediaItem ] {
        let deduped = items.filter { item in
            !seenKeys.contains(key(for: item))
        }
        
        let result = deduped.count >= minimumCount ? deduped : items
        
        for item in result {
            seenKeys.insert(key(for: item))
        }
        
        return result
    }
    
    private func key(for item: any MediaItem) -> String {
        "\(item.mediaType.rawValue)-\(item.id)"
    }
}
