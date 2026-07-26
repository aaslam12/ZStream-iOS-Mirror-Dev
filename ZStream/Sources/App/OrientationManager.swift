//
//  OrientationManager.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import SwiftUI

final class OrientationManager: ObservableObject {
    static let shared = OrientationManager()
    var allowsLandscape = false {
        didSet {
            if #available(iOS 16.0, *) {
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .forEach { $0.requestGeometryUpdate(.iOS(interfaceOrientations: allowsLandscape ? .all : .portrait)) }
            } else {
                UIViewController.attemptRotationToDeviceOrientation()
            }
        }
    }
}
