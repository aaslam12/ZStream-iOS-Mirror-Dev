//
//  GenreHelper.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/18/26.
//

import Foundation
import SwiftUI

enum GenreColors {
    static let gradients: [Int: [Color]] = [
        28: [.red, .orange],                                     // Action
        12: [.green, .yellow],                                   // Adventure
        16: [.yellow, .pink],                                    // Animation
        35: [.orange, .purple],                                  // Comedy
        80: [.gray, .black],                                     // Crime
        99: [.teal, .blue],                                      // Documentary
        18: [.indigo, .purple],                                  // Drama
        10751: [.pink, .orange],                                 // Family
        14: [.purple, .blue],                                    // Fantasy
        36: [.brown, .orange],                                   // History
        27: [.black, .red],                                      // Horror
        10402: [.mint, .teal],                                   // Music
        9648: [.indigo, .cyan],                                  // Mystery
        10749: [.red, Color(red: 0.85, green: 0.2, blue: 0.55)], // Romance
        878: [.blue, .cyan],                                     // Science Fiction
        10770: [.gray, .blue],                                   // TV Movie
        53: [.red, .black],                                      // Thriller
        10752: [.brown, .gray],                                  // War
        37: [.orange, .brown]                                    // Western
    ]

    static func gradient(for genreId: Int) -> [Color] {
        gradients[genreId] ?? [.gray, .black]
    }
}

// Helper to get the genre images
enum GenreImages {
    static let assetNames: [Int: String] = [
        28: "Genres/action",
        12: "Genres/adventure",
        16: "Genres/animation",
        35: "Genres/comedy",
        80: "Genres/crime",
        99: "Genres/documentary",
        18: "Genres/drama",
        10751: "Genres/family",
        14: "Genres/fantasy",
        36: "Genres/history",
        27: "Genres/horror",
        10402: "Genres/music",
        9648: "Genres/mystery",
        10749: "Genres/romance",
        878: "Genres/science-fiction",
        10770: "Genres/tv-movie",
        53: "Genres/thriller",
        10752: "Genres/war",
        37: "Genres/western"
    ]

    static func assetName(for genreId: Int) -> String {
        assetNames[genreId] ?? "Genres/action"
    }
}
