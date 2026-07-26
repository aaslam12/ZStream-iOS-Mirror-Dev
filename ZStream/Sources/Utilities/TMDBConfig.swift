//
//  TMDBConfig.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/16/26.
//

import Foundation

/// Config for TMDB from the env vars
enum TMDBConfig {
    static let accessToken: String = {
        guard let token = Bundle.main.object(forInfoDictionaryKey: "TMDB_ACCESS_TOKEN") as? String,
              !token.isEmpty else {
            fatalError("TMDB_ACCESS_TOKEN missing — check Config.xcconfig exists and is linked to your build configuration.")
        }
        return token
    }()
}
