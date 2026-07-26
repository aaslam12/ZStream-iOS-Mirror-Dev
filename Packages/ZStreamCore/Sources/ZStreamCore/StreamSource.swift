//
//  StreamSource.swift
//  ZStreamCore
//
//  Contract between the app and a stream source implementation.
//
//  Rules:
//  - resolve() must never throw. Return .error instead.
//  - resolve() must be safe to call concurrently, even though the app's
//    resolution loop calls sources sequentially today.
//  - The source receives only what it needs: a MediaRequest and a sourceId.
//

import Foundation

public protocol StreamSource {
    /// Build version. Must increase monotonically with each release.
    var version: Int { get }

    /// Returns the list of sources this provides, in its preferred default
    /// order. The app may reorder these based on user preference. Must
    /// return a stable list — do not shuffle or randomise.
    func availableSources() -> [SourceInfo]

    /// Attempt to resolve a playable stream for `media` using the source identified
    /// by `sourceId`. Called once per source by the app's resolution loop.
    ///
    /// `sourceId` will always be a value previously returned by `availableSources()`.
    /// If `sourceId` is unrecognised, return `.error`.
    func resolve(media: MediaRequest, sourceId: String) async -> StreamResult
}
