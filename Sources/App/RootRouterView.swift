import SwiftUI

struct RootRouterView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        Group {
            switch router.screen {
            case .connectionGuide:
                ConnectionGuideView()
            case .carMode:
                CarModeView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: router.screen)
    }
}
