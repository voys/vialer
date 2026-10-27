import SwiftUI
import Contacts
import AVFoundation
import UserNotifications

enum OnboardingStep: Hashable {
    case login
    case password
    case twoFactor
    case permission(PermissionKind)
    case mobileNumber
    case welcome
}

enum PermissionKind: Hashable {
    case contacts, microphone, notifications

    var title: String {
        switch self {
        case .contacts: return L10n.onboarding.permission.contacts.title
        case .microphone: return L10n.onboarding.permission.microphone.title
        case .notifications: return L10n.onboarding.permission.notifications.title
        }
    }

    var systemImage: String {
        switch self {
        case .contacts: return "person.crop.circle"
        case .microphone: return "mic"
        case .notifications: return "bell"
        }
    }

    var description: String {
        switch self {
        case .contacts: return L10n.onboarding.permission.contacts.description(appName: Brand.appName)
        case .microphone: return L10n.onboarding.permission.microphone.description(appName: Brand.appName)
        case .notifications: return L10n.onboarding.permission.notifications.description(appName: Brand.appName)
        }
    }

    func isGranted() async -> Bool {
        switch self {
        case .contacts:
            return CNContactStore.authorizationStatus(for: .contacts) != .notDetermined
        case .microphone:
            return AVAudioApplication.shared.recordPermission != .undetermined
        case .notifications:
            return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus != .notDetermined
        }
    }

    func request() async {
        switch self {
        case .contacts:
            _ = try? await CNContactStore().requestAccess(for: .contacts)
        case .microphone:
            _ = await AVAudioApplication.requestRecordPermission()
        case .notifications:
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
    }
}

/// Login → (password) → (two factor) → permissions → mobile number → welcome.
@MainActor
@Observable
final class OnboardingModel {
    var steps: [OnboardingStep] = [.login]
    var index = 0
    var email = ""
    var password = ""

    var current: OnboardingStep { steps[index] }

    func insert(_ step: OnboardingStep, after: OnboardingStep) {
        guard !steps.contains(step), let i = steps.firstIndex(of: after) else { return }
        steps.insert(step, at: i + 1)
    }

    func next() {
        if index + 1 < steps.count { index += 1 }
    }

    func back() {
        if index > 0 { index -= 1 }
    }

    /// After login, add the permission steps that still need asking, then mobile number and welcome.
    func appendPostLoginSteps() async {
        var remaining: [OnboardingStep] = []
        for kind in [PermissionKind.contacts, .microphone, .notifications] where !(await kind.isGranted()) {
            remaining.append(.permission(kind))
        }
        remaining += [.mobileNumber, .welcome]
        steps = Array(steps.prefix(index + 1)) + remaining
    }
}

struct OnboardingFlow: View {
    @Environment(AppContainer.self) private var container
    @State private var model = OnboardingModel()

    var body: some View {
        ZStack {
            OnboardingBackground()
            Group {
                switch model.current {
                case .login: LoginView(model: model)
                case .password: PasswordChangeView(model: model)
                case .twoFactor: TwoFactorView(model: model)
                case .permission(let kind): PermissionView(kind: kind, model: model)
                case .mobileNumber: MobileNumberView(model: model)
                case .welcome: WelcomeView()
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            .id(model.current)
        }
        .animation(.easeInOut(duration: 0.25), value: model.index)
    }
}

private struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            GeometryReader { geo in
                Path { p in
                    p.move(to: .zero)
                    p.addLine(to: CGPoint(x: geo.size.width, y: 0))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * 0.28))
                    p.closeSubpath()
                }
                .fill(Theme.primaryGradient)
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Login

struct LoginView: View {
    @Environment(AppContainer.self) private var container
    @Bindable var model: OnboardingModel
    @State private var isLoading = false
    @State private var error: String?
    @State private var showPassword = false
    @State private var showForgotPassword = false
    @State private var resetRequested = false
    @FocusState private var focus: Field?

    enum Field { case email, password }

    private var strings: L10n.onboarding.login.Type { L10n.onboarding.login.self }

    private var isEmailValid: Bool {
        model.email.range(of: "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", options: .regularExpression) != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Spacer(minLength: 120)
                Text(strings.title)
                    .font(.largeTitle.bold())

                VStack(alignment: .leading, spacing: 8) {
                    TextField(strings.placeholder.email, text: $model.email)
                        .textFieldStyle(StylizedTextFieldStyle())
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }

                    HStack {
                        Group {
                            if showPassword {
                                TextField(strings.placeholder.password, text: $model.password)
                            } else {
                                SecureField(strings.placeholder.password, text: $model.password)
                            }
                        }
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await login() } }
                        Button { showPassword.toggle() } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye").foregroundStyle(Theme.grey4)
                        }
                    }
                    .padding(12)
                    .overlay(RoundedRectangle(cornerRadius: Theme.fieldCornerRadius).stroke(Theme.grey1))
                }

                if let error {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(Theme.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.fieldCornerRadius))
                }

                Button {
                    Task { await login() }
                } label: {
                    if isLoading { ProgressView().tint(.white) } else { Text(L10n.onboarding.button.login) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isLoading || model.email.isEmpty || model.password.isEmpty || !container.connectivity.isConnected)

                if !container.connectivity.isConnected {
                    Text(L10n.connectivity.noConnection.message).font(.footnote).foregroundStyle(Theme.red)
                }

                Button(strings.button.forgotPassword) { showForgotPassword = true }
                    .buttonStyle(PrimaryButtonStyle(filled: false))

                Link(strings.button.privacyPolicy, destination: Brand.privacyPolicyURL)
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            #if DEBUG
            if model.email.isEmpty, model.password.isEmpty,
               let username = DevCredentials.username, let password = DevCredentials.password {
                model.email = username
                model.password = password
            }
            #endif
        }
        .sheet(isPresented: $showForgotPassword) {
            PasswordForgottenView(email: model.email) { resetRequested = true }
        }
        .alert(N("onboarding.passwordForgotten.requested.title"), isPresented: $resetRequested) {
            Button(L10n.generic.button.ok) {}
        } message: {
            Text(L10n.onboarding.passwordForgotten.success)
        }
    }

    private func login() async {
        guard isEmailValid else {
            error = strings.error.wrongEmailFormat
            return
        }
        error = nil
        isLoading = true
        defer { isLoading = false }
        switch await container.session.login(email: model.email, password: model.password) {
        case .success:
            await model.appendPostLoginSteps()
            model.next()
        case .twoFactorRequired:
            model.insert(.twoFactor, after: .login)
            model.next()
        case .passwordChangeRequired:
            model.insert(.password, after: .login)
            model.next()
        case .invalidCredentials:
            error = strings.error.wrongCombination.message
        case .noConnection:
            error = L10n.connectivity.noConnection.message
        case .failed(let message):
            error = N("onboarding.login.error.generic", ["message": message])
        }
    }
}

struct PasswordForgottenView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State var email: String
    @State private var isLoading = false
    @State private var failed = false
    var onRequested: () -> Void

    private var strings: L10n.onboarding.passwordForgotten.Type { L10n.onboarding.passwordForgotten.self }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(strings.description)
                    .foregroundStyle(Theme.infoText)
                TextField(L10n.onboarding.login.placeholder.email, text: $email)
                    .textFieldStyle(StylizedTextFieldStyle())
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if failed {
                    Text(N("onboarding.passwordForgotten.error"))
                        .font(.subheadline).foregroundStyle(Theme.red)
                }
                Button {
                    Task {
                        isLoading = true
                        let ok = await container.session.requestPasswordReset(email: email)
                        isLoading = false
                        if ok { dismiss(); onRequested() } else { failed = true }
                    }
                } label: {
                    if isLoading { Text(strings.button.requestingPasswordReset) } else { Text(strings.button.requestPasswordReset) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(email.isEmpty || isLoading)
                Spacer()
            }
            .padding(24)
            .navigationTitle(strings.title.replacingOccurrences(of: "\n", with: " "))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.generic.button.cancel) { dismiss() } } }
        }
    }
}

// MARK: - Forced password change

struct PasswordChangeView: View {
    @Environment(AppContainer.self) private var container
    @Bindable var model: OnboardingModel
    @State private var newPassword = ""
    @State private var isLoading = false
    @State private var error: String?

    private var strings: L10n.onboarding.password.Type { L10n.onboarding.password.self }

    private var isValid: Bool {
        newPassword.count >= 6 && newPassword.range(of: "[^A-Za-z]", options: .regularExpression) != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Spacer(minLength: 120)
                Text(strings.title).font(.largeTitle.bold())
                Text(strings.description).foregroundStyle(Theme.infoText)
                SecureField(L10n.onboarding.login.placeholder.password, text: $newPassword)
                    .textFieldStyle(StylizedTextFieldStyle())
                    .textContentType(.newPassword)
                Text(strings.requirements).font(.footnote).foregroundStyle(Theme.infoText)
                if let error {
                    Text(error).font(.subheadline).foregroundStyle(Theme.red)
                }
                Button {
                    Task { await change() }
                } label: {
                    if isLoading { ProgressView().tint(.white) } else { Text(strings.button) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!isValid || isLoading)
            }
            .padding(24)
        }
    }

    private func change() async {
        isLoading = true
        defer { isLoading = false }
        error = nil
        let ok = await container.session.changePassword(email: model.email, currentPassword: model.password, newPassword: newPassword)
        guard ok else {
            error = strings.error.message
            return
        }
        model.password = newPassword
        switch await container.session.login(email: model.email, password: newPassword) {
        case .success:
            await model.appendPostLoginSteps()
            model.next()
        case .twoFactorRequired:
            model.insert(.twoFactor, after: .password)
            model.next()
        default:
            error = N("onboarding.password.error.login")
        }
    }
}

// MARK: - Two factor

struct TwoFactorView: View {
    @Environment(AppContainer.self) private var container
    @Bindable var model: OnboardingModel
    @State private var code = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var success = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Spacer(minLength: 120)
                Text(N("onboarding.twoFactor.title")).font(.largeTitle.bold())
                Text(N("onboarding.twoFactor.description")).foregroundStyle(Theme.infoText)

                HStack(spacing: 10) {
                    ForEach(0..<6, id: \.self) { i in
                        let char = i < code.count ? String(Array(code)[i]) : ""
                        Text(char)
                            .font(.title.monospacedDigit())
                            .frame(width: 44, height: 56)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(i == code.count ? Theme.primary : Theme.grey1, lineWidth: 1.5))
                    }
                }
                .frame(maxWidth: .infinity)
                .overlay(
                    TextField("", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($focused)
                        .opacity(0.02)
                )
                .onTapGesture { focused = true }
                .onChange(of: code) { _, value in
                    code = String(value.filter(\.isNumber).prefix(6))
                    if code.count == 6 { Task { await submit() } }
                }

                if let error { Text(error).font(.subheadline).foregroundStyle(Theme.red) }
                if success {
                    Label(N("onboarding.twoFactor.verified"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green)
                }
                if isLoading { ProgressView().frame(maxWidth: .infinity) }
            }
            .padding(24)
        }
        .onAppear { focused = true }
    }

    private func submit() async {
        isLoading = true
        defer { isLoading = false }
        error = nil
        switch await container.session.login(email: model.email, password: model.password, twoFactorCode: code) {
        case .success:
            success = true
            await model.appendPostLoginSteps()
            try? await Task.sleep(for: .seconds(0.8))
            model.next()
        case .invalidCredentials:
            error = N("onboarding.twoFactor.error.incorrect")
            code = ""
        case .noConnection:
            error = L10n.connectivity.noConnection.message
        default:
            error = N("onboarding.twoFactor.error.generic")
            code = ""
        }
    }
}

// MARK: - Permissions

struct PermissionView: View {
    let kind: PermissionKind
    @Bindable var model: OnboardingModel

    var body: some View {
        InfoPage(systemImage: kind.systemImage, title: kind.title, description: kind.description, buttonTitle: L10n.onboarding.permission.button.iUnderstand) {
            await kind.request()
            model.next()
        }
    }
}

struct InfoPage: View {
    var systemImage: String
    var title: String
    var description: String
    var buttonTitle: String
    var action: () async -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 64))
                .foregroundStyle(Theme.primary)
            Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(description)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.infoText)
            Spacer()
            Button(buttonTitle) { Task { await action() } }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
    }
}

// MARK: - Mobile number

struct MobileNumberView: View {
    @Environment(AppContainer.self) private var container
    @Bindable var model: OnboardingModel
    @State private var number = ""
    @State private var isLoading = false
    @State private var error: String?

    private var strings: L10n.onboarding.mobileNumber.Type { L10n.onboarding.mobileNumber.self }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Spacer(minLength: 120)
                Text(strings.title).font(.largeTitle.bold())
                Text(strings.description(appName: Brand.appName)).foregroundStyle(Theme.infoText)
                TextField(strings.hint, text: $number)
                    .textFieldStyle(StylizedTextFieldStyle())
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                Text(strings.info).font(.footnote).foregroundStyle(Theme.infoText)
                if let error { Text(error).font(.subheadline).foregroundStyle(Theme.red) }
                Button {
                    Task { await save() }
                } label: {
                    if isLoading { ProgressView().tint(.white) } else { Text(number.isEmpty ? L10n.generic.button.skip : strings.button) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isLoading)
            }
            .padding(24)
        }
        .onAppear { number = container.session.settings.mobileNumber }
    }

    private func save() async {
        let trimmed = number.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        guard !trimmed.isEmpty else {
            model.next()
            return
        }
        isLoading = true
        defer { isLoading = false }
        guard await PhoneNumberAPI().isStrictlyValidMobileNumber(trimmed) else {
            error = strings.error
            return
        }
        if await container.session.changeMobileNumber(trimmed) {
            model.next()
        } else {
            error = N("onboarding.mobileNumber.error.save")
        }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text(N("onboarding.welcome", ["appName": Brand.appName])).font(.largeTitle.bold())
            Text(container.session.user?.firstName ?? "").font(.title2).foregroundStyle(Theme.infoText)
            Spacer()
        }
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            container.onboardingCompleted()
        }
    }
}
