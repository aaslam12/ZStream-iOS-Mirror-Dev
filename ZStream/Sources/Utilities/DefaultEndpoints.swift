//
//  DefaultEndpoints.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import Foundation

enum DefaultEndpoints {
    static let base = "https://court.fontaine.lol"

    static func meta() -> URL { URL(string: "\(base)/meta")! }
    static func registerStart() -> URL { URL(string: "\(base)/auth/register/start")! }
    static func registerComplete() -> URL { URL(string: "\(base)/auth/register/complete")! }
    static func loginStart() -> URL { URL(string: "\(base)/auth/login/start")! }
    static func loginComplete() -> URL { URL(string: "\(base)/auth/login/complete")! }
    static func rekeyStart() -> URL { URL(string: "\(base)/auth/rekey/start")! }
    static func rekeyComplete() -> URL { URL(string: "\(base)/auth/rekey/complete")! }
    static func me() -> URL { URL(string: "\(base)/users/@me")! }

    // MARK: User library

    static func bookmarks(userId: String) -> URL {
        URL(string: "\(base)/users/\(userId)/bookmarks")!
    }
    static func bookmark(userId: String, tmdbId: String) -> URL {
        URL(string: "\(base)/users/\(userId)/bookmarks/\(tmdbId)")!
    }
    static func watchHistory(userId: String) -> URL {
        URL(string: "\(base)/users/\(userId)/watch-history")!
    }
    static func watchHistoryItem(userId: String, tmdbId: String) -> URL {
        URL(string: "\(base)/users/\(userId)/watch-history/\(tmdbId)")!
    }
}
