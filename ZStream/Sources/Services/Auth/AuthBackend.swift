//
//  AuthBackend.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import Foundation

/// Main object the whole application uses.
/// Swap the `current` implementation to point the whole app at a different backend.
enum AuthBackend {
    static var current: AuthProtocol = DefaultAuthRepository()
}
