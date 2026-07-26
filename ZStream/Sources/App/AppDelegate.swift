//
//  AppDelegate.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Stashed by the system when it launches/wakes the app in the background
    /// to deliver events for our downloads' background URLSession (a transfer
    /// finished or failed while the app wasn't in the foreground). Must be
    /// called — once DownloadManager's session reports
    /// `urlSessionDidFinishEvents(forBackgroundURLSession:)` — or iOS may
    /// throttle/kill the app before the download is actually committed to disk.
    var backgroundDownloadsCompletionHandler: (() -> Void)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        backgroundDownloadsCompletionHandler = completionHandler
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationManager.shared.allowsLandscape ? .all : .portrait
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
