import SwiftUI

struct RootView: View {
    @EnvironmentObject var bootstrapper: Bootstrapper
    @EnvironmentObject var settings: AppSettings
    @State private var splashMinimumTimeElapsed = false
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash {
                SplashView {
                    splashMinimumTimeElapsed = true
                }
            } else {
                MainView()
            }
        }
        .tint(settings.theme.accent)
        .task {
            await bootstrapper.start()
        }
        .onChange(of: splashMinimumTimeElapsed) { _, elapsed in
            checkReadyToProceed(elapsed: elapsed)
        }
        .onChange(of: bootstrapper.phase) { _, _ in
            checkReadyToProceed(elapsed: splashMinimumTimeElapsed)
        }
    }

    private func checkReadyToProceed(elapsed: Bool) {
        guard elapsed, bootstrapper.phase == .ready else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            showSplash = false
        }
    }
}
