import SwiftUI

struct RootRouterView: View {
    @EnvironmentObject private var router: AppRouter
    private let phoneCanvasMaxWidth: CGFloat = 430

    var body: some View {
        GeometryReader { proxy in
            Group {
                switch router.screen {
                case .connectionGuide:
                    ConnectionGuideView()
                case .carMode:
                    CarModeView()
                }
            }
            .frame(maxWidth: min(phoneCanvasMaxWidth, proxy.size.width))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeInOut(duration: 0.2), value: router.screen)
    }
}
