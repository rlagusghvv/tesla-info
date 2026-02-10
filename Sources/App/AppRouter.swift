import Foundation

@MainActor
final class AppRouter: ObservableObject {
    enum Screen {
        case connectionGuide
        case carMode
    }

    enum TriggerReason: String {
        case launch
        case alreadyConnected
        case networkConnected
        case manualShortcut
        case deepLink
    }

    @Published private(set) var screen: Screen = .connectionGuide
    @Published private(set) var lastReason: TriggerReason = .launch

    func showGuide() {
        screen = .connectionGuide
    }

    func enterCarMode(reason: TriggerReason) {
        lastReason = reason
        screen = .carMode
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "myapp" else { return }

        let host = url.host?.lowercased() ?? ""
        if host == "car" || url.path.lowercased() == "/car" {
            enterCarMode(reason: .deepLink)
        }
    }
}
