import SwiftUI
import UIKit

@main
struct TeslaSubDashApp: App {
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var router = AppRouter()
    @StateObject private var teslaAuth = TeslaAuthStore.shared
    @StateObject private var kakaoConfig = KakaoConfigStore.shared
    @StateObject private var subscription = SubscriptionManager.shared

    var body: some Scene {
        WindowGroup {
            RootRouterView()
                .environmentObject(networkMonitor)
                .environmentObject(router)
                .environmentObject(teslaAuth)
                .environmentObject(kakaoConfig)
                .environmentObject(subscription)
                .onAppear {
                    // Stability-first launch: do not auto-enter Car Mode on app start.
                    // Car Mode should start only via explicit user action (button/shortcut/deeplink).
                    consumeStartCarModeFlagIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    consumeStartCarModeFlagIfNeeded()
                }
                .onOpenURL { url in
                    if url.scheme == "myapp", (url.host?.lowercased() == "oauth") {
                        teslaAuth.handleOAuthCallbackURL(url)
                        return
                    }

                    router.handleDeepLink(url)
                }
        }
    }

    private func consumeStartCarModeFlagIfNeeded() {
        let shouldLaunchCarMode = UserDefaults.standard.bool(forKey: LaunchFlags.startCarModeFromIntent)
        guard shouldLaunchCarMode else { return }
        UserDefaults.standard.set(false, forKey: LaunchFlags.startCarModeFromIntent)
        if networkMonitor.isConnected, teslaAuth.isSignedIn {
            router.enterCarMode(reason: .manualShortcut)
        } else {
            router.showGuide()
        }
    }
}
