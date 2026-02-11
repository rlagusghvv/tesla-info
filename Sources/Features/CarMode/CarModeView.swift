import SwiftUI

struct CarModeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var teslaAuth: TeslaAuthStore
    @StateObject private var viewModel = CarModeViewModel()
    @StateObject private var naviModel = KakaoNavigationViewModel()
    @State private var showSetupSheet = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.05, green: 0.09, blue: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            content
                .padding(16)

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
            let sideWidth = max(240, min(280, proxy.size.width * 0.30))

            HStack(spacing: 14) {
                centerPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                sidePanel
                    .frame(width: sideWidth)
            }
        }
    }

    private var centerPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                CenterModeSegmentedControl(selection: $viewModel.centerMode)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)

                headerIconButton(systemImage: "arrow.clockwise") {
                    Task { await viewModel.refresh() }
                }
                .disabled(!networkMonitor.isConnected)

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
                case .map:
                    TelemetryMapView(location: viewModel.snapshot.vehicle.location)
                case .navi:
                    KakaoNavigationPaneView(
                        model: naviModel,
                        vehicleLocation: viewModel.snapshot.vehicle.location,
                        vehicleSpeedKph: viewModel.snapshot.vehicle.speedKph,
                        wakeVehicle: {
                            viewModel.sendCommand("wake_up")
                            Task {
                                // Wake can take a while; retry refresh multiple times to reduce manual tapping.
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
                InAppBrowserView(url: mediaURL)
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
                            .font(.system(size: 24, weight: .bold, design: .rounded))
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
                    }
                }

                controlsGrid

                Button {
                    router.showGuide()
                } label: {
                    Label("Exit Car Mode", systemImage: "arrowshape.turn.up.backward.fill")
                }
                .buttonStyle(SecondaryCarButtonStyle(fontSize: 20, height: 64, cornerRadius: 18))

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
            .buttonStyle(SecondaryCarButtonStyle(fontSize: 20, height: 64, cornerRadius: 18))
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
            return PrimaryCarButtonStyle(fontSize: 20, height: 64, cornerRadius: 18)
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
        .font(.system(size: 19, weight: .semibold, design: .rounded))
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
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
