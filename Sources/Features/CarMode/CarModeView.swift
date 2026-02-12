import SwiftUI
import WebKit

private final class WebViewStore: ObservableObject {
    let webView: WKWebView

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        self.webView = WKWebView(frame: .zero, configuration: configuration)
    }
}

struct CarModeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var teslaAuth: TeslaAuthStore
    @StateObject private var viewModel = CarModeViewModel()
    @StateObject private var naviModel = KakaoNavigationViewModel()
    @State private var showSetupSheet = false
    @State private var showMediaOverlayInNavi = false
    @State private var naviHUDVisible: Bool = true
    @State private var showChromeInNavi: Bool = false
    @State private var autoHideTask: Task<Void, Never>?

    @StateObject private var mediaWebViewStore = WebViewStore()
    @State private var mediaOverlaySize: CGSize = .zero
    @State private var mediaOverlayOrigin: CGPoint = .zero
    @State private var mediaOverlayDragAnchor: CGPoint = .zero
    @State private var mediaOverlayResizeAnchor: CGSize = .zero
    @State private var hasInitializedMediaOverlay = false

    private let mediaToolbarHeight: CGFloat = 64
    private let mediaMinSize = CGSize(width: 330, height: 220)
    private let regularTopInset: CGFloat = 22

    var body: some View {
        GeometryReader { root in
            let isFullscreenNavi = viewModel.centerMode == .navi && !showChromeInNavi

            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.05, green: 0.09, blue: 0.16)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                content
                    .padding(.horizontal, isFullscreenNavi ? 0 : 16)
                    .padding(.top, isFullscreenNavi ? 0 : max(regularTopInset, root.safeAreaInsets.top + 14))
                    .padding(.bottom, isFullscreenNavi ? 0 : max(12, root.safeAreaInsets.bottom + 8))

                if !teslaAuth.isSignedIn {
                    VStack(spacing: 14) {
                        Text("Tesla login required")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Exit Car Mode to connect your Tesla account.")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))

                        Button {
                            showSetupSheet = true
                        } label: {
                            Label("Go to Tesla Account", systemImage: "person.crop.circle")
                        }
                        .buttonStyle(SecondaryCarButtonStyle())
                        .frame(height: 70)
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                            )
                    )
                    .padding(24)
                }
            }
        }
        .onAppear {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
            autoHideTask?.cancel()
            autoHideTask = nil
        }
        .onChange(of: scenePhase) { _, next in
            switch next {
            case .active:
                viewModel.start()
            case .inactive, .background:
                viewModel.stop()
            @unknown default:
                break
            }
        }
        .onChange(of: showSetupSheet) { _, presented in
            // Pause polling while editing account/setup fields to avoid UI hitches on older iPads.
            if presented {
                viewModel.stop()
            } else if scenePhase == .active {
                viewModel.start()
            }
        }
        .sheet(isPresented: $showSetupSheet) {
            ConnectionGuideView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var content: some View {
        GeometryReader { proxy in
            // Keep the center pane dominant (map/media), especially on iPad mini.
            // All vehicle info + controls live in a single side bar.
            let sideWidth = max(198, min(230, proxy.size.width * 0.24))

            HStack(spacing: (viewModel.centerMode == .navi && !showChromeInNavi) ? 0 : 14) {
                if showSetupSheet {
                    suspendedCenterPanel
                } else {
                    centerPanel
                }

                if !(viewModel.centerMode == .navi && !showChromeInNavi) {
                    Group {
                        if showSetupSheet {
                            suspendedSidePanel
                        } else {
                            sidePanel
                        }
                    }
                    .frame(width: sideWidth)

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var suspendedCenterPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                CenterModeSegmentedControl(selection: $viewModel.centerMode)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)

                headerIconButton(systemImage: "person.crop.circle.fill") {}
                    .disabled(true)
            }

            VStack(spacing: 10) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))

                Text("Setup Mode")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("Map and polling are paused for stability while Account is open.")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )

            Text("Source: \(viewModel.snapshot.source)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private var suspendedSidePanel: some View {
        VStack(spacing: 12) {
            card {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.snapshot.vehicle.displayName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Account panel active")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }

            card {
                Text("Controls are temporarily paused.")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var centerPanel: some View {
        if viewModel.centerMode == .navi, !showChromeInNavi {
            fullscreenNaviPanel
        } else {
            regularCenterPanel
        }
    }

    private var fullscreenNaviPanel: some View {
        ZStack(alignment: .bottomTrailing) {
            naviPane
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleChromeInNavi()
                }

            if showMediaOverlayInNavi, let mediaURL = viewModel.mediaURL {
                DraggableMediaOverlay(url: mediaURL, webView: mediaWebViewStore.webView)
                    .padding(14)
            }

            // Keep access to Account / Controls even in fullscreen mode.
            VStack(spacing: 10) {
                headerIconButton(systemImage: "hand.tap") {
                    toggleChromeInNavi()
                }
                headerIconButton(systemImage: "person.crop.circle") {
                    showSetupSheet = true
                }
            }
            .padding(.trailing, 12)
            .padding(.top, 16)
            .safeAreaPadding(.top, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .ignoresSafeArea()
    }

    private var naviPane: some View {
        KakaoNavigationPaneView(
            model: naviModel,
            vehicleLocation: viewModel.snapshot.vehicle.location,
            vehicleSpeedKph: viewModel.snapshot.vehicle.speedKph,
            wakeVehicle: {
                viewModel.sendCommand("wake_up")
                Task {
                    for attempt in 0..<6 {
                        let waitSeconds = attempt == 0 ? 5 : 4
                        try? await Task.sleep(nanoseconds: UInt64(waitSeconds) * 1_000_000_000)
                        await viewModel.refresh()
                        if viewModel.snapshot.vehicle.location.isValid {
                            break
                        }
                    }
                }
            },
            hudVisible: $naviHUDVisible
        )
    }

    private var regularCenterPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                CenterModeSegmentedControl(selection: $viewModel.centerMode)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)

                headerIconButton(systemImage: "arrow.clockwise") {
                    Task { await viewModel.refresh() }
                }
                .disabled(!networkMonitor.isConnected)

                if viewModel.centerMode == .navi {
                    headerIconButton(systemImage: showMediaOverlayInNavi ? "rectangle.on.rectangle.slash" : "rectangle.on.rectangle") {
                        showMediaOverlayInNavi.toggle()
                    }

                    headerIconButton(systemImage: showChromeInNavi ? "hand.tap.fill" : "hand.tap") {
                        toggleChromeInNavi()
                    }
                }

                headerIconButton(systemImage: "person.crop.circle") {
                    showSetupSheet = true
                }
            }

            if !networkMonitor.isConnected {
                HStack(spacing: 10) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Offline. Waiting for hotspot internet.")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
            }

            Group {
                switch viewModel.centerMode {
                case .navi:
                    ZStack(alignment: .bottomTrailing) {
                        naviPane
                        if showMediaOverlayInNavi, let mediaURL = viewModel.mediaURL {
                            DraggableMediaOverlay(url: mediaURL, webView: mediaWebViewStore.webView)
                                .frame(width: 360, height: 220)
                                .padding(14)
                        }
                    }
                case .media:
                    mediaPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                Text("Source: \(viewModel.snapshot.source)")
                    .foregroundStyle(.white.opacity(0.75))
                Text("Updated: \(viewModel.snapshot.updatedAt)")
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private func toggleChromeInNavi() {
        let shouldShow = !showChromeInNavi
        showChromeInNavi = shouldShow

        autoHideTask?.cancel()
        autoHideTask = nil

        guard shouldShow else { return }

        // Auto-hide after a few seconds to keep the map unobstructed.
        autoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if viewModel.centerMode == .navi {
                showChromeInNavi = false
            }
        }
    }

    private func headerIconButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.16))
                )
        }
        .buttonStyle(.plain)
    }

    private struct CenterModeSegmentedControl: View {
        @Binding var selection: CarModeViewModel.CenterMode

        var body: some View {
            HStack(spacing: 0) {
                ForEach(CarModeViewModel.CenterMode.allCases, id: \.self) { mode in
                    Button {
                        selection = mode
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(selection == mode ? 1.0 : 0.75))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background {
                        if selection == mode {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.16))
                                .padding(4)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
        }
    }

    private struct DraggableMediaOverlay: View {
        let url: URL
        let webView: WKWebView

        @State private var offset: CGSize = .zero
        @GestureState private var dragTranslation: CGSize = .zero

        // Resize is implemented by changing the overlay frame (NOT web page zoom).
        @State private var size: CGSize = CGSize(width: 360, height: 220)

        private let minSize = CGSize(width: 240, height: 160)
        private let maxSize = CGSize(width: 920, height: 720)

        private let presetS = CGSize(width: 320, height: 200)
        private let presetM = CGSize(width: 420, height: 260)
        private let presetL = CGSize(width: 560, height: 340)
        private let presetFull = CGSize(width: 860, height: 620)

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("Media")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))

                    Spacer()

                    Button("-") { scale(by: 0.90) }
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.10)))

                    Button("+") { scale(by: 1.10) }
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.10)))

                    Button("S") { applyPreset(presetS) }
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.10)))

                    Button("M") { applyPreset(presetM) }
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.10)))

                    Button("L") { applyPreset(presetL) }
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.10)))

                    Button("Full") { applyPreset(presetFull) }
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(height: 26)
                        .padding(.horizontal, 8)
                        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.10)))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.55))

                InAppBrowserView(url: url, persistentWebView: webView)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .overlay(alignment: .bottomTrailing) {
                resizeHandle
            }
            .shadow(color: Color.black.opacity(0.35), radius: 16, x: 0, y: 10)
            .offset(x: offset.width + dragTranslation.width, y: offset.height + dragTranslation.height)
            .gesture(
                DragGesture()
                    .updating($dragTranslation) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                    }
            )
        }

        private var resizeHandle: some View {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.black.opacity(0.55)))
                .padding(10)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let next = CGSize(width: size.width + value.translation.width, height: size.height + value.translation.height)
                            size = clampSize(next)
                        }
                )
        }

        private func clampSize(_ raw: CGSize) -> CGSize {
            CGSize(
                width: min(maxSize.width, max(minSize.width, raw.width)),
                height: min(maxSize.height, max(minSize.height, raw.height))
            )
        }

        private func applyPreset(_ preset: CGSize) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                size = clampSize(preset)
            }
        }

        private func scale(by factor: CGFloat) {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                size = clampSize(CGSize(width: size.width * factor, height: size.height * factor))
            }
        }
    }

    private var mediaPane: some View {
        GeometryReader { proxy in
            let containerSize = proxy.size

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )

                HStack(spacing: 8) {
                    Button("YouTube") {
                        viewModel.mediaURLText = "https://m.youtube.com"
                    }
                    .buttonStyle(SecondaryCarButtonStyle(fontSize: 16, height: 48, cornerRadius: 12))

                    Button("CHZZK") {
                        viewModel.mediaURLText = "https://chzzk.naver.com"
                    }
                    .buttonStyle(SecondaryCarButtonStyle(fontSize: 16, height: 48, cornerRadius: 12))

                    Spacer(minLength: 8)

                    Button("-") {
                        scaleMediaOverlay(by: 0.90, in: containerSize)
                    }
                    .buttonStyle(SecondaryCarButtonStyle(fontSize: 18, height: 42, cornerRadius: 12))
                    .frame(width: 42)

                    Button("+") {
                        scaleMediaOverlay(by: 1.10, in: containerSize)
                    }
                    .buttonStyle(SecondaryCarButtonStyle(fontSize: 18, height: 42, cornerRadius: 12))
                    .frame(width: 42)

                    ForEach(MediaOverlayPreset.allCases, id: \.self) { preset in
                        Button(preset.label) {
                            applyMediaPreset(preset, in: containerSize)
                        }
                        .buttonStyle(SecondaryCarButtonStyle(fontSize: 14, height: 42, cornerRadius: 10))
                        .frame(width: preset == .full ? 56 : 44)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .frame(height: mediaToolbarHeight)

                if let mediaURL = viewModel.mediaURL {
                    mediaWindow(url: mediaURL, containerSize: containerSize)
                } else {
                    Text("Invalid media URL")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onAppear {
                initializeMediaOverlayIfNeeded(in: containerSize)
            }
            .onChange(of: containerSize) { _, next in
                initializeMediaOverlayIfNeeded(in: next)
                clampMediaOverlay(in: next)
            }
        }
    }

    private var sidePanel: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewModel.snapshot.vehicle.displayName)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(viewModel.snapshot.vehicle.onlineState.uppercased())
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))

                        Divider().overlay(Color.white.opacity(0.2))

                        metricRow(title: "Speed", value: viewModel.speedText)
                        metricRow(title: "Battery", value: viewModel.batteryText)
                        metricRow(title: "Range", value: viewModel.rangeText)
                        metricRow(title: "Lock", value: viewModel.lockText)
                        metricRow(title: "Climate", value: viewModel.climateText)
                    }
                }

                card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Location")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                        Text(viewModel.locationText)
                            .font(.system(size: 17, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.7)
                    }
                }

                if let message = viewModel.errorMessage {
                    card {
                        Text(message)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.red.opacity(0.95))
                            .lineLimit(6)
                            .truncationMode(.tail)
                    }
                }

                controlsGrid

                Button {
                    router.showGuide()
                } label: {
                    Label("Exit Car Mode", systemImage: "arrowshape.turn.up.backward.fill")
                }
                .buttonStyle(SecondaryCarButtonStyle(fontSize: 17, height: 54, cornerRadius: 14))

                if viewModel.isCommandRunning {
                    card {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(.white)
                            Text("Sending command...")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                }

                if let commandMessage = viewModel.commandMessage {
                    card {
                        Text(commandMessage)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func mediaWindow(url: URL, containerSize: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))

                Text("Media Overlay")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))

                Spacer(minLength: 0)

                Text("\(Int(mediaOverlaySize.width.rounded())) x \(Int(mediaOverlaySize.height.rounded()))")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color.black.opacity(0.30))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let proposal = CGPoint(
                            x: mediaOverlayDragAnchor.x + value.translation.width,
                            y: mediaOverlayDragAnchor.y + value.translation.height
                        )
                        mediaOverlayOrigin = clampedMediaOrigin(proposal, size: mediaOverlaySize, container: containerSize)
                    }
                    .onEnded { _ in
                        mediaOverlayDragAnchor = mediaOverlayOrigin
                    }
            )

            InAppBrowserView(url: url, persistentWebView: mediaWebViewStore.webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: mediaOverlaySize.width, height: mediaOverlaySize.height)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.40))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(Color.white.opacity(0.90))
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.black.opacity(0.85))
                )
                .padding(8)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            let next = CGSize(
                                width: mediaOverlayResizeAnchor.width + value.translation.width,
                                height: mediaOverlayResizeAnchor.height + value.translation.height
                            )
                            mediaOverlaySize = clampedMediaSize(next, container: containerSize)
                            mediaOverlayOrigin = clampedMediaOrigin(mediaOverlayOrigin, size: mediaOverlaySize, container: containerSize)
                        }
                        .onEnded { _ in
                            mediaOverlayResizeAnchor = mediaOverlaySize
                            mediaOverlayDragAnchor = mediaOverlayOrigin
                        }
                )
        }
        .position(
            x: mediaOverlayOrigin.x + (mediaOverlaySize.width / 2.0),
            y: mediaOverlayOrigin.y + (mediaOverlaySize.height / 2.0)
        )
    }

    private func initializeMediaOverlayIfNeeded(in container: CGSize) {
        guard container.width > 0, container.height > 0 else { return }
        guard !hasInitializedMediaOverlay else { return }

        let initial = clampedMediaSize(
            CGSize(width: container.width * 0.62, height: container.height * 0.58),
            container: container
        )
        let origin = CGPoint(
            x: max(10, (container.width - initial.width) / 2.0),
            y: mediaToolbarHeight + 10
        )

        mediaOverlaySize = initial
        mediaOverlayOrigin = clampedMediaOrigin(origin, size: initial, container: container)
        mediaOverlayDragAnchor = mediaOverlayOrigin
        mediaOverlayResizeAnchor = mediaOverlaySize
        hasInitializedMediaOverlay = true
    }

    private func clampMediaOverlay(in container: CGSize) {
        guard hasInitializedMediaOverlay else { return }
        mediaOverlaySize = clampedMediaSize(mediaOverlaySize, container: container)
        mediaOverlayOrigin = clampedMediaOrigin(mediaOverlayOrigin, size: mediaOverlaySize, container: container)
        mediaOverlayDragAnchor = mediaOverlayOrigin
        mediaOverlayResizeAnchor = mediaOverlaySize
    }

    private func scaleMediaOverlay(by factor: CGFloat, in container: CGSize) {
        guard hasInitializedMediaOverlay else {
            initializeMediaOverlayIfNeeded(in: container)
            return
        }
        let proposal = CGSize(
            width: mediaOverlaySize.width * factor,
            height: mediaOverlaySize.height * factor
        )
        mediaOverlaySize = clampedMediaSize(proposal, container: container)
        mediaOverlayOrigin = clampedMediaOrigin(mediaOverlayOrigin, size: mediaOverlaySize, container: container)
        mediaOverlayResizeAnchor = mediaOverlaySize
        mediaOverlayDragAnchor = mediaOverlayOrigin
    }

    private func applyMediaPreset(_ preset: MediaOverlayPreset, in container: CGSize) {
        guard container.width > 0, container.height > 0 else { return }
        let target: CGSize
        switch preset {
        case .small:
            target = CGSize(width: container.width * 0.44, height: container.height * 0.34)
        case .medium:
            target = CGSize(width: container.width * 0.58, height: container.height * 0.48)
        case .large:
            target = CGSize(width: container.width * 0.74, height: container.height * 0.65)
        case .full:
            target = CGSize(width: container.width * 0.95, height: container.height - mediaToolbarHeight - 16)
        }

        mediaOverlaySize = clampedMediaSize(target, container: container)
        let centered = CGPoint(
            x: (container.width - mediaOverlaySize.width) / 2.0,
            y: mediaToolbarHeight + 8
        )
        mediaOverlayOrigin = clampedMediaOrigin(centered, size: mediaOverlaySize, container: container)
        mediaOverlayResizeAnchor = mediaOverlaySize
        mediaOverlayDragAnchor = mediaOverlayOrigin
        hasInitializedMediaOverlay = true
    }

    private func clampedMediaSize(_ proposal: CGSize, container: CGSize) -> CGSize {
        let maxWidth = max(mediaMinSize.width, container.width - 20)
        let maxHeight = max(mediaMinSize.height, container.height - mediaToolbarHeight - 12)
        return CGSize(
            width: min(max(proposal.width, mediaMinSize.width), maxWidth),
            height: min(max(proposal.height, mediaMinSize.height), maxHeight)
        )
    }

    private func clampedMediaOrigin(_ proposal: CGPoint, size: CGSize, container: CGSize) -> CGPoint {
        let minX: CGFloat = 10
        let minY: CGFloat = mediaToolbarHeight + 6
        let maxX = max(minX, container.width - size.width - 10)
        let maxY = max(minY, container.height - size.height - 10)
        return CGPoint(
            x: min(max(proposal.x, minX), maxX),
            y: min(max(proposal.y, minY), maxY)
        )
    }

    private enum MediaOverlayPreset: CaseIterable {
        case small
        case medium
        case large
        case full

        var label: String {
            switch self {
            case .small:
                return "S"
            case .medium:
                return "M"
            case .large:
                return "L"
            case .full:
                return "Full"
            }
        }
    }

    private var controlsGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]

        return LazyVGrid(columns: columns, spacing: 10) {
            controlButton(title: "Lock", symbol: "lock.fill", command: "door_lock", variant: .compact)
            controlButton(title: "Unlock", symbol: "lock.open.fill", command: "door_unlock", variant: .compact)
            controlButton(title: "A/C ON", symbol: "wind", command: "auto_conditioning_start", variant: .compact)
            controlButton(title: "A/C OFF", symbol: "snowflake", command: "auto_conditioning_stop", variant: .compact)
            controlButton(title: "Wake", symbol: "bolt.fill", command: "wake_up", variant: .compact)
            Button {
                showSetupSheet = true
            } label: {
                Label("Account", systemImage: "person.crop.circle")
            }
            .buttonStyle(SecondaryCarButtonStyle(fontSize: 17, height: 54, cornerRadius: 14))
        }
    }

    private enum ControlButtonVariant {
        case regular
        case compact
    }

    private func controlButton(title: String, symbol: String, command: String, variant: ControlButtonVariant = .regular) -> some View {
        Button {
            viewModel.sendCommand(command)
        } label: {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(primaryStyle(for: variant))
        .disabled(viewModel.isCommandRunning || !networkMonitor.isConnected)
    }

    private func primaryStyle(for variant: ControlButtonVariant) -> PrimaryCarButtonStyle {
        switch variant {
        case .regular:
            return PrimaryCarButtonStyle(fontSize: 22, height: 80, cornerRadius: 20)
        case .compact:
            return PrimaryCarButtonStyle(fontSize: 17, height: 54, cornerRadius: 14)
        }
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            Text(value)
                .foregroundStyle(.white)
                .fontWeight(.bold)
        }
        .font(.system(size: 16, weight: .semibold, design: .rounded))
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
    }
}
