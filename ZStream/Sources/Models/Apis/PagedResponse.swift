//
//  PagedResponse.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//
import Foundation

/// Generic API response with paging support
struct PagedResponse<T: Decodable>: Decodable {
    let page: Int
    let results: [T]
    let totalPages: Int

    enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages"
    }
}
