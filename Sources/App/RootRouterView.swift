import SwiftUI

struct RootRouterView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var adminSession: AdminSessionStore
    private let phoneCanvasMaxWidth: CGFloat = 430

    var body: some View {
        GeometryReader { proxy in
            Group {
                if adminSession.isLoggedIn {
                    switch router.screen {
                    case .connectionGuide:
                        ConnectionGuideView()
                    case .carMode:
                        CarModeView()
                    }
                } else {
                    AdminLoginGateView()
                }
            }
            .frame(maxWidth: min(phoneCanvasMaxWidth, proxy.size.width))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .animation(.easeInOut(duration: 0.2), value: router.screen)
        .animation(.easeInOut(duration: 0.2), value: adminSession.isLoggedIn)
    }
}

private struct AdminLoginGateView: View {
    private enum AuthMode: String, CaseIterable, Identifiable {
        case login
        case signup

        var id: String { rawValue }
    }

    @EnvironmentObject private var adminSession: AdminSessionStore
    @State private var mode: AuthMode = .login
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var showPassword: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(mode == .login ? "Subdash 로그인" : "Subdash 회원가입")
                    .font(.title2.bold())

                Text(mode == .login
                     ? "로그인 후 계정별 Tesla/Kakao 키를 자동으로 불러옵니다."
                     : "회원가입 후 바로 로그인되어 본인 Tesla/Kakao 키를 저장할 수 있습니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Picker("Auth Mode", selection: $mode) {
                    Text("로그인").tag(AuthMode.login)
                    Text("회원가입").tag(AuthMode.signup)
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _, _ in
                    adminSession.statusMessage = nil
                    password = ""
                    confirmPassword = ""
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Backend URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("https://your-backend.example.com", text: $adminSession.backendURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled(true)
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Username")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("username", text: $adminSession.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Group {
                        if showPassword {
                            TextField("Password", text: $password)
                        } else {
                            SecureField("Password", text: $password)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Toggle("비밀번호 보기", isOn: $showPassword)
                        .font(.caption)
                }

                if mode == .signup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password 확인")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Group {
                            if showPassword {
                                TextField("Confirm Password", text: $confirmPassword)
                            } else {
                                SecureField("Confirm Password", text: $confirmPassword)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                Button(action: submit) {
                    Text(adminSession.isBusy
                         ? (mode == .login ? "로그인 중..." : "가입 중...")
                         : (mode == .login ? "로그인" : "회원가입"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(adminSession.isBusy)

                if let message = adminSession.statusMessage, !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func submit() {
        let currentPassword = password
        let currentConfirm = confirmPassword
        Task {
            switch mode {
            case .login:
                await adminSession.login(password: currentPassword)
            case .signup:
                await adminSession.signup(password: currentPassword, confirmPassword: currentConfirm)
            }
            if adminSession.isLoggedIn {
                password = ""
                confirmPassword = ""
            }
        }
    }
}
