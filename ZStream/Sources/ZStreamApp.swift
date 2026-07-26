import SwiftUI

@main
struct ZStreamApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var contentStore: ContentStore
    @StateObject private var settings: AppSettings
    @StateObject private var bootstrapper: Bootstrapper
    @StateObject private var sessionStore = SessionManager()
    @StateObject private var downloadManager = DownloadManager()

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        AppLogger.shared.start()
        DiagnosticsLog.shared.start()
        print("——— ZStream launched ———")

        // URL Caching limits
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,   // 50Mb in ram
            diskCapacity: 500 * 1024 * 1024,    // 500Mb on disk
            directory: nil
        )
        
        let settings = AppSettings()
        let contentStore = ContentStore()
        
        _settings = StateObject(wrappedValue: settings)
        _contentStore = StateObject(wrappedValue: contentStore)
        _bootstrapper = StateObject(wrappedValue: Bootstrapper(contentStore: contentStore, settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(contentStore)
                .environmentObject(settings)
                .environmentObject(bootstrapper)
                .environmentObject(sessionStore)
                .environmentObject(downloadManager)
        }
    }
}
