//
//  MediaCollections.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import Foundation

struct CollectionSearchResult: Decodable {
    let id: Int
    let name: String
}

struct CollectionDetail: Decodable {
    let id: Int
    let name: String
    let parts: [Movie]
}
