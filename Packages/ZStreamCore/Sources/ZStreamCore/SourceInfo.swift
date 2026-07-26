//
//  SourceInfo.swift
//  ZStreamCore
//

import Foundation

/// Describes a single stream source the app knows about.
/// Used to build the per-source status list in the player UI.
public struct SourceInfo {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}
