//
//  Credits.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import Foundation

struct Credits: Codable {
    let cast: [CastMember]
    let crew: [CrewMember]

    struct CastMember: Codable, Identifiable {
        let id: Int
        let name: String
        let character: String
        let profilePath: String?

        var profileURL: URL? {
            guard let profilePath else { return nil }
            return URL(string: "https://image.tmdb.org/t/p/w185\(profilePath)")
        }

        enum CodingKeys: String, CodingKey {
            case id, name, character
            case profilePath = "profile_path"
        }
    }

    struct CrewMember: Codable, Identifiable {
        let id: Int
        let name: String
        let job: String
        let profilePath: String?

        var profileURL: URL? {
            guard let profilePath else { return nil }
            return URL(string: "https://image.tmdb.org/t/p/w185\(profilePath)")
        }

        enum CodingKeys: String, CodingKey {
            case id, name, job
            case profilePath = "profile_path"
        }
    }

    var director: CrewMember? {
        crew.first { $0.job == "Director" }
    }
}
