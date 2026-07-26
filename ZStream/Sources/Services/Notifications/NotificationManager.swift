//
//  NotificationManager.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/21/26.
//

import Foundation
import UserNotifications
import UIKit

@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private override init() {
        super.init()
        Task { await refreshAuthorizationStatus() }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Call this the moment the user does something that actually needs
    /// notifications (e.g. taps "Notify Me!") — never at app launch. Asking
    /// cold, with no context, is the #1 reason people reflexively deny.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        await refreshAuthorizationStatus()

        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])
                await refreshAuthorizationStatus()
                return granted
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    // MARK: - One-time, at a specific date

    func scheduleOneTime(id: String, title: String, body: String, date: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleTest(id: String, title: String, body: String, secondsFromNow: TimeInterval) {
        
        Task {
            let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            print("📋 Currently pending: \(pending.count)/64")
        }
    
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: secondsFromNow, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("❌ Notification scheduling FAILED for \(id): \(error)")
            } else {
                print("✅ Notification scheduled successfully: \(id), firing in \(secondsFromNow)s")
            }
        }
    }
    
    // MARK: - Recurring

    enum RecurrenceFrequency {
        case daily(hour: Int, minute: Int)
        case weekly(weekday: Int, hour: Int, minute: Int) // 1 = Sunday ... 7 = Saturday
    }

    func scheduleRecurring(id: String, title: String, body: String, frequency: RecurrenceFrequency) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var components = DateComponents()
        switch frequency {
        case .daily(let hour, let minute):
            components.hour = hour
            components.minute = minute
        case .weekly(let weekday, let hour, let minute):
            components.weekday = weekday
            components.hour = hour
            components.minute = minute
        }

        // repeats: true + a DateComponents trigger is the whole mechanism —
        // iOS re-fires it every time the given components next match
        // (e.g. every day at 9:00, or every Sunday at 9:00), no manual
        // rescheduling needed after each fire.
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    static func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
