//
//  SourceStatus.swift
//  ZStreamCore
//

import Foundation

public enum SourceStatus {
    case idle
    case trying
    case success
    case failed
}

public struct SourceResult {
    public let id: String
    public var status: SourceStatus
    public var codec: String = ""

    public init(id: String, status: SourceStatus, codec: String = "") {
        self.id = id
        self.status = status
        self.codec = codec
    }
}
