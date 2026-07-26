//
//  Caption.swift
//  ZStreamCore
//

import Foundation

/// A single subtitle/caption track returned by a source alongside a resolved stream.
public struct Caption {
    public let url: String
    public let language: String
    public let langIso: String
    public let type: String // "vtt", "srt", etc.

    public init(url: String, language: String, langIso: String, type: String) {
        self.url = url
        self.language = language
        self.langIso = langIso
        self.type = type
    }
}
