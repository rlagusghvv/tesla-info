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
    @State private var showChromeInNavi: Bool = false
    @State private var autoHideTask: Task<Void, Never>?

    @StateObject private var mediaWebViewStore = WebViewStore()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.05, green: 0.09, blue: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            content
                .padding(viewModel.centerMode == .navi && !showChromeInNavi ? 0 : 16)

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
        .onAppear {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
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

    private var centerPanel: some View {
        // Fullscreen Navi: hide chrome unless explicitly shown.
        if viewModel.centerMode == .navi, !showChromeInNavi {
            return AnyView(
                ZStack(alignment: .bottomTrailing) {
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
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleChromeInNavi()
                    }

                    if showMediaOverlayInNavi, let mediaURL = viewModel.mediaURL {
                        DraggableMediaOverlay(url: mediaURL, webView: mediaWebViewStore.webView)
                            .frame(width: 360, height: 220)
                            .padding(14)
                    }
                }
                .ignoresSafeArea()
            )
        }

        return AnyView(
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
                                }
                            )

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

        @State private var scale: CGFloat = 1.0
        @GestureState private var magnification: CGFloat = 1.0

        private let minScale: CGFloat = 0.65
        private let maxScale: CGFloat = 1.9

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("Media")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))

                    Spacer()

                    Button("-") { scale = max(minScale, scale - 0.12) }
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.10)))

                    Button("+") { scale = min(maxScale, scale + 0.12) }
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.10)))

                    Button("S") { scale = 0.75 }
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.10)))

                    Button("M") { scale = 1.0 }
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.10)))

                    Button("L") { scale = 1.35 }
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.10)))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.55))

                InAppBrowserView(url: url, persistentWebView: webView)
            }
            .scaleEffect(scale * magnification)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
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
            .simultaneousGesture(
                MagnificationGesture()
                    .updating($magnification) { value, state, _ in
                        state = value
                    }
                    .onEnded { value in
                        let next = scale * value
                        scale = min(maxScale, max(minScale, next))
                    }
            )
        }
    }

    private var mediaPane: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button("YouTube") {
                    viewModel.mediaURLText = "https://m.youtube.com"
                }
                .buttonStyle(SecondaryCarButtonStyle(fontSize: 20, height: 64, cornerRadius: 18))

                Button("CHZZK") {
                    viewModel.mediaURLText = "https://chzzk.naver.com"
                }
                .buttonStyle(SecondaryCarButtonStyle(fontSize: 20, height: 64, cornerRadius: 18))
            }
            .frame(height: 66)

            if let mediaURL = viewModel.mediaURL {
                InAppBrowserView(url: mediaURL, persistentWebView: mediaWebViewStore.webView)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                Text("Invalid media URL")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
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
