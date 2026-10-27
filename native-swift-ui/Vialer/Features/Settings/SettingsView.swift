import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppContainer.self) private var container
    @State private var confirmLogout = false
    @State private var errorMessage: String?

    private var session: SessionManager { container.session }
    private var strings: L10n.main.settings.Type { L10n.main.settings.self }

    var body: some View {
        NavigationStack {
            settingsList
                .navigationTitle(strings.title)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var settingsList: some View {
        List {
                BannerSection(horizontalPadding: 0)
                if let until = session.rateLimitedUntil {
                    Section {
                        RateLimitBanner(until: until)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                header
                AvailabilitySection(errorMessage: $errorMessage)
                Section {
                    NavigationLink(strings.subPage.appPreferences.title) { AppPreferencesView() }
                    NavigationLink(strings.subPage.user.title(user: session.user?.fullName ?? "")) { UserSettingsView() }
                    if let user = session.user, ClientSettingsView.isAvailable(for: user) {
                        NavigationLink(strings.subPage.client.title(client: user.client.name)) { ClientSettingsView() }
                    }
                    NavigationLink { AboutView() } label: {
                        Text(strings.subPage.aboutTheApp.title).badge(session.hasUnreadFeatureAnnouncements ? N("settings.about.new") : nil)
                    }
                }
                Section {
                    Button(strings.buttons.logout, role: .destructive) { confirmLogout = true }
                }
            }
            .contentMargins(.top, 8, for: .scrollContent)
            .disabled(session.isRateLimited)
            .refreshable { await session.refreshUser(force: true) }
            .confirmationDialog(N("settings.logoutConfirm", ["appName": Brand.appName]), isPresented: $confirmLogout, titleVisibility: .visible) {
                Button(strings.buttons.logout, role: .destructive) { container.logout() }
            }
            .alert(N("settings.error.title"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button(L10n.generic.button.ok) {}
            } message: { Text(errorMessage ?? "") }
    }

    private var header: some View {
        Section {
            HStack(spacing: 16) {
                AvatarView(name: session.user?.fullName ?? "", size: 56, statusColor: session.settings.availabilityStatus.color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.user?.fullName ?? "").font(.headline)
                    Text([session.user?.internalNumber, session.user?.email].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " - "))
                        .font(.subheadline).foregroundStyle(Theme.infoText)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Shown for a minute after the API answers 429, like the Flutter rate-limit snackbar.
struct RateLimitBanner: View {
    let until: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = max(0, Int(until.timeIntervalSince(context.date).rounded(.up)))
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.red)
                Text(L10n.rateLimiting.snackbar.message(appName: Brand.appName, seconds: String(seconds)))
                    .font(.subheadline)
            }
            .bannerCard(Theme.red.opacity(0.12))
        }
    }
}

// MARK: - Availability

struct AvailabilitySection: View {
    @Environment(AppContainer.self) private var container
    @Binding var errorMessage: String?
    @State private var isUpdating = false

    private var session: SessionManager { container.session }
    private var status: UserAvailabilityStatus { session.settings.availabilityStatus }
    private var devicesEnabled: Bool { status == .available || status == .availableForColleagues }
    /// Remote settings can't be changed offline or while rate limited, as in the Flutter app.
    private var canChangeRemoteSettings: Bool { container.connectivity.isConnected && !session.isRateLimited }

    var body: some View {
        Section {
            Menu {
                ForEach(UserAvailabilityStatus.allCases, id: \.self) { s in
                    Button {
                        Task { await change(status: s) }
                    } label: { Label(s.title, systemImage: s.systemImage) }
                }
            } label: {
                HStack {
                    Image(systemName: status.systemImage)
                    Text(status.title)
                    if session.isRingingDeviceOffline && status != .offline {
                        Text(N("settings.availability.ringingDeviceOffline")).font(.caption)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
                .padding(12)
                .foregroundStyle(status.foregroundColor)
                .background(status.backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: Theme.fieldCornerRadius))
            }
            .disabled(isUpdating || !canChangeRemoteSettings)
            .accessibilityLabel(L10n.main.settings.list.calling.availability.screenReader.status.selection(status: status.title))

            ringingDevices
                .opacity(devicesEnabled ? 1 : 0.5)
                .disabled(!devicesEnabled || isUpdating || !canChangeRemoteSettings)
        } header: {
            Text(N("settings.availability.title"))
        } footer: {
            if !container.connectivity.isConnected {
                Text(N("settings.availability.offlineHint"))
            }
        }
    }

    private var ringingDevices: some View {
        let user = session.user
        let destinations = session.availableDestinations
        let app = user.flatMap { destinations.appAccount(for: $0) }
        let webphone = user.flatMap { destinations.webphoneAccount(for: $0) }
        let desk = user.map { destinations.deskPhones(for: $0) } ?? []
        let fixed = destinations.fixedDestinations
        let selected = session.selectedDestination

        return VStack(alignment: .leading, spacing: 8) {
            Text(N("settings.ringingDevice.title")).font(.caption).foregroundStyle(Theme.infoText)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                if let app {
                    DeviceButton(title: N("settings.ringingDevice.mobile"), systemImage: "iphone", isSelected: selected == app, isOffline: !app.isOnline) {
                        Task { await change(destination: app) }
                    }
                }
                DeviceGroupButton(title: N("settings.ringingDevice.deskPhone"), systemImage: "phone.fill", options: desk, selected: selected) { destination in Task { await change(destination: destination) } }
                if let webphone {
                    DeviceButton(title: N("settings.ringingDevice.webphone"), systemImage: "desktopcomputer", isSelected: selected == webphone, isOffline: !webphone.isOnline) {
                        Task { await change(destination: webphone) }
                    }
                }
                DeviceGroupButton(title: N("settings.ringingDevice.fixedDestination"), systemImage: "arrow.turn.down.right", options: fixed, selected: selected) { destination in Task { await change(destination: destination) } }
            }
            if !selected.isOnline, devicesEnabled {
                Text(L10n.main.colleagues.status.selectedDeviceOffline).font(.caption).foregroundStyle(Theme.red)
            }
        }
        .padding(.vertical, 4)
    }

    private func change(status: UserAvailabilityStatus) async {
        isUpdating = true
        defer { isUpdating = false }
        if !(await session.changeAvailabilityStatus(status)) {
            errorMessage = N("settings.error.availability")
        }
    }

    private func change(destination: Destination) async {
        isUpdating = true
        defer { isUpdating = false }
        if !(await session.changeDestination(destination)) {
            errorMessage = N("settings.error.ringingDevice")
        }
    }
}

private struct DeviceButton: View {
    var title: String
    var systemImage: String
    var isSelected: Bool
    var isOffline = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            DeviceLabel(title: title, systemImage: systemImage, isSelected: isSelected, isOffline: isOffline)
        }
        .buttonStyle(.plain)
    }
}

/// The device tile itself; also used as a `Menu` label, where a `Button` would swallow the tap.
private struct DeviceLabel: View {
    var title: String
    var systemImage: String
    var isSelected: Bool
    var isOffline = false

    var body: some View {
        HStack {
            Image(systemName: systemImage)
            Text(title).lineLimit(1)
            Spacer()
            if isOffline { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.red).font(.caption) }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(isSelected ? Theme.primary : Theme.grey7)
        .foregroundStyle(isSelected ? .white : .primary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.fieldCornerRadius))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isOffline ? "\(title), \(L10n.main.colleagues.status.selectedDeviceOffline)" : title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct DeviceGroupButton: View {
    var title: String
    var systemImage: String
    var options: [Destination]
    var selected: Destination
    var onSelect: (Destination) -> Void

    var body: some View {
        if options.isEmpty {
            DeviceLabel(title: title, systemImage: systemImage, isSelected: false).opacity(0.4)
        } else if options.count == 1, let only = options.first {
            DeviceButton(title: only.description.isEmpty ? title : only.description, systemImage: systemImage, isSelected: selected == only, isOffline: !only.isOnline) {
                onSelect(only)
            }
        } else {
            let current = options.first { $0 == selected }
            Menu {
                ForEach(options, id: \.identifier) { option in
                    Button { onSelect(option) } label: {
                        if selected == option {
                            Label(option.description, systemImage: "checkmark")
                        } else {
                            Text(option.description)
                        }
                    }
                }
            } label: {
                DeviceLabel(title: current?.description ?? title, systemImage: systemImage, isSelected: current != nil, isOffline: current.map { !$0.isOnline } ?? false)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
    }
}

// MARK: - App preferences

struct AppPreferencesView: View {
    @Environment(AppContainer.self) private var container
    @State private var error: String?

    private var list: L10n.main.settings.list.Type { L10n.main.settings.list.self }

    var body: some View {
        @Bindable var session = container.session
        List {
            Section(list.calling.title) {
                if session.user?.isAllowedVoipCalling == true {
                    Toggle(isOn: $session.settings.useVoip) {
                        Text(list.calling.useVoip.title)
                        Text(list.calling.useVoip.description).font(.caption)
                    }
                    .onChange(of: session.settings.useVoip) { _, enabled in
                        container.calls.middleware.isVoipEnabled = enabled
                        if enabled, let user = session.user {
                            container.calls.start(user: user, settings: session.settings)
                            container.calls.middleware.register()
                        } else {
                            container.calls.middleware.unregister()
                            Task { await container.calls.stop() }
                        }
                    }
                }
                if session.settings.useVoip, session.user?.hasPermission(.canChangeMobileNumberFallback) == true {
                    Toggle(isOn: Binding(
                        get: { session.settings.useMobileNumberAsFallback },
                        set: { value in Task { if !(await session.setUseMobileNumberAsFallback(value)) { error = N("settings.error.generic") } } }
                    )) {
                        Text(list.calling.useMobileNumberAsFallback.title)
                        Text(list.calling.useMobileNumberAsFallback.description(mobileNumber: session.settings.mobileNumber)).font(.caption)
                    }
                }
                Toggle(isOn: $session.settings.showCallsInNativeRecents) {
                    Text(list.calling.showCallsInNativeRecents.title)
                    Text(list.calling.showCallsInNativeRecents.description(app: Brand.appName)).font(.caption)
                }
                .onChange(of: session.settings.showCallsInNativeRecents) { _, _ in container.calls.updatePreferences(settings: session.settings) }
            }
            Section(list.recents.title) {
                if session.user?.hasPermission(.canSeeClientCalls) == true {
                    Toggle(isOn: $session.settings.showClientCalls) {
                        Text(list.calling.showClientCalls.title)
                        Text(list.calling.showClientCalls.description).font(.caption)
                    }
                }
                Toggle(isOn: $session.settings.alwaysShowCallerNameInRecents) {
                    Text(list.recents.alwaysShowCallerName.title)
                    Text(list.recents.alwaysShowCallerName.description).font(.caption)
                }
            }
            Section(list.audio.title) {
                if session.user?.isAllowedVoipCalling == true {
                    Toggle(isOn: $session.settings.usePhoneRingtone) {
                        Text(list.audio.usePhoneRingtone.title)
                        Text(list.audio.usePhoneRingtone.description(appName: Brand.appName)).font(.caption)
                    }
                    .onChange(of: session.settings.usePhoneRingtone) { _, _ in container.calls.updatePreferences(settings: session.settings) }
                }
            }
            Section(list.debug.title) {
                Toggle(isOn: $session.settings.remoteLogging) {
                    Text(list.debug.remoteLogging.title)
                    Text(list.debug.remoteLogging.description).font(.caption)
                }
                .onChange(of: session.settings.remoteLogging) { _, value in RemoteLogging.shared.isEnabled = value }
                NavigationLink(N("settings.logs.title")) { LogsView() }
            }
            if session.settings.showTroubleshooting {
                Section(list.advancedSettings.title) {
                    Toggle(isOn: Binding(
                        get: { container.calls.isAdvancedLoggingEnabled },
                        set: { container.calls.setAdvancedLogging($0) }
                    )) {
                        Text(list.advancedSettings.enableAdvancedVoipLogging.title)
                        Text(list.advancedSettings.enableAdvancedVoipLogging.description + " " + N("settings.advancedVoipLogging.disabledAtLaunch")).font(.caption)
                    }
                    NavigationLink(list.advancedSettings.troubleshooting.title) { TroubleshootingView() }
                }
            }
        }
        .navigationTitle(L10n.main.settings.subPage.appPreferences.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert(N("settings.error.title"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(L10n.generic.button.ok) {}
        } message: { Text(error ?? "") }
    }
}

struct TroubleshootingView: View {
    @Environment(AppContainer.self) private var container
    @State private var calibrating = false

    private var strings: L10n.main.settings.list.advancedSettings.troubleshooting.Type {
        L10n.main.settings.list.advancedSettings.troubleshooting.self
    }

    var body: some View {
        List {
            Section {
                Text(strings.description).font(.footnote).foregroundStyle(Theme.infoText)
            }
            if container.session.canUseVoip {
                Section(strings.list.audio.title) {
                    Button {
                        container.calls.performEchoCancellationCalibration()
                        calibrating = true
                        Task { try? await Task.sleep(for: .seconds(8)); calibrating = false }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(strings.list.audio.echoCancellationCalibration.title).foregroundStyle(.primary)
                                if calibrating { Spacer(); ProgressView() }
                            }
                            Text(strings.list.audio.echoCancellationCalibration.description).font(.caption).foregroundStyle(Theme.infoText)
                        }
                    }
                    .disabled(calibrating)
                }
            }
            Section(strings.versionInfo.title) {
                LabeledContent(L10n.main.settings.list.version, value: "\(BuildInfo.version) (\(BuildInfo.buildNumber))")
                LabeledContent(N("settings.about.linphone"), value: container.calls.linphoneVersion ?? N("settings.about.notStarted"))
                LabeledContent("iOS", value: BuildInfo.osVersion)
            }
            Section(strings.logs.title) {
                NavigationLink(N("settings.logs.title")) { LogsView() }
            }
            Section {
                NavigationLink(strings.featureFlags.title) { FeatureFlagsView() }
            }
        }
        .navigationTitle(strings.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LogsView: View {
    @State private var lines: [String] = []

    var body: some View {
        ScrollView {
            Text(lines.joined(separator: "\n"))
                .font(.system(size: 10, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(N("settings.logs.title"))
        .task {
            while !Task.isCancelled {
                lines = AppLog.buffer.suffix(300)
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { UIPasteboard.general.string = AppLog.buffer.joined(separator: "\n") } label: { Image(systemName: "doc.on.doc") }
                    .accessibilityLabel(L10n.main.recent.list.item.popupMenu.copy)
            }
        }
    }
}

// MARK: - User

struct UserSettingsView: View {
    @Environment(AppContainer.self) private var container
    @State private var editMobile = false
    @State private var mobileDraft = ""
    @State private var showOutgoing = false
    @State private var error: String?

    private var session: SessionManager { container.session }
    private var info: L10n.main.settings.list.accountInfo.Type { L10n.main.settings.list.accountInfo.self }
    private var canChangeRemoteSettings: Bool { container.connectivity.isConnected && !session.isRateLimited }

    var body: some View {
        List {
            Section {
                Button {
                    mobileDraft = session.settings.mobileNumber
                    editMobile = true
                } label: {
                    LabeledContent(info.mobileNumber.title, value: session.settings.mobileNumber.isEmpty ? N("settings.notSet") : session.settings.mobileNumber)
                }
                .foregroundStyle(.primary)
                if session.user?.hasPermission(.canChangeOutgoingNumber) == true {
                    Button { showOutgoing = true } label: {
                        HStack {
                            LabeledContent(info.businessNumber.title, value: session.settings.outgoingNumber.displayLabel.isEmpty ? N("settings.notSet") : session.settings.outgoingNumber.displayLabel)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.grey4)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                LabeledContent(info.username.title, value: session.user?.email ?? "")
            } footer: {
                Text(container.connectivity.isConnected ? info.businessNumber.description : L10n.connectivity.noConnection.message)
            }
            .disabled(!canChangeRemoteSettings)
            Section {
                NavigationLink(L10n.main.settings.changePassword.title) { ChangePasswordView() }
            }
            .disabled(!canChangeRemoteSettings)
        }
        .navigationTitle(L10n.main.settings.subPage.user.title(user: session.user?.fullName ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .alert(info.mobileNumber.title, isPresented: $editMobile) {
            TextField(info.mobileNumber.help, text: $mobileDraft).keyboardType(.phonePad)
            Button(N("generic.save")) {
                Task {
                    let cleaned = mobileDraft.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
                    guard await PhoneNumberAPI().isStrictlyValidMobileNumber(cleaned) else {
                        error = L10n.onboarding.mobileNumber.error
                        return
                    }
                    if !(await session.changeMobileNumber(cleaned)) { error = N("settings.error.mobileNumber") }
                }
            }
            Button(L10n.generic.button.cancel, role: .cancel) {}
        } message: {
            Text(info.mobileNumber.description)
        }
        .sheet(isPresented: $showOutgoing) { OutgoingNumberPicker() }
        .alert(N("settings.error.title"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(L10n.generic.button.ok) {}
        } message: { Text(error ?? "") }
    }
}

struct OutgoingNumberPicker: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var error: String?

    private var session: SessionManager { container.session }
    private var strings: L10n.main.settings.list.accountInfo.businessNumber.Type { L10n.main.settings.list.accountInfo.businessNumber.self }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(.suppressed)
                }
                let recents = session.recentOutgoingNumbers
                if !recents.isEmpty {
                    Section(strings.section.recently) { ForEach(recents, id: \.self) { row($0) } }
                }
                Section(strings.section.other) {
                    ForEach(session.user?.client.outgoingNumbers ?? [], id: \.self) { row($0) }
                }
                if let error { Section { Text(error).foregroundStyle(Theme.red) } }
            }
            .navigationTitle(strings.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.generic.button.cancel) { dismiss() } } }
            .disabled(isSaving)
        }
    }

    private func row(_ number: OutgoingNumber) -> some View {
        Button {
            Task {
                isSaving = true
                let ok = await session.changeOutgoingNumber(number)
                isSaving = false
                if ok { dismiss() } else { error = N("settings.error.outgoingNumber") }
            }
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(number.isSuppressed ? strings.suppressed : number.value).foregroundStyle(.primary)
                    if let d = number.description, !d.isEmpty { Text(d).font(.caption).foregroundStyle(Theme.infoText) }
                }
                Spacer()
                if number == session.settings.outgoingNumber { Image(systemName: "checkmark").foregroundStyle(Theme.primary) }
            }
        }
    }
}

struct ChangePasswordView: View {
    @Environment(AppContainer.self) private var container
    @State private var current = ""
    @State private var new = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var done = false

    private var strings: L10n.main.settings.changePassword.Type { L10n.main.settings.changePassword.self }
    private var isValid: Bool { !current.isEmpty && new.count >= 6 && new.range(of: "[^A-Za-z]", options: .regularExpression) != nil }

    var body: some View {
        Form {
            Section {
                SecureField(strings.current.title, text: $current).textContentType(.password)
                SecureField(strings.newpassword.title, text: $new).textContentType(.newPassword)
            } footer: {
                Text("\(strings.newpassword.description)\n\n\(strings.apiTokenChangeNotice)")
            }
            if let error { Section { Text(error).foregroundStyle(Theme.red) } }
            Section {
                Button {
                    Task { await change() }
                } label: {
                    if isLoading { ProgressView() } else { Text(strings.actions.save) }
                }
                .disabled(!isValid || isLoading)
            }
        }
        .navigationTitle(strings.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert(strings.changed, isPresented: $done) {
            Button(L10n.generic.button.ok) { container.logout() }
        } message: { Text(strings.loginAgain) }
    }

    private func change() async {
        guard let email = container.session.user?.email else { return }
        isLoading = true
        defer { isLoading = false }
        if await container.session.changePassword(email: email, currentPassword: current, newPassword: new) {
            done = true
        } else {
            error = strings.errors.currentInvalid
        }
    }
}

// MARK: - About

struct AboutView: View {
    @Environment(AppContainer.self) private var container
    @State private var versionTaps = 0
    @State private var showAnnouncements = false
    @State private var unlockMessage: String?

    var body: some View {
        List {
            Section {
                Button { showAnnouncements = true } label: {
                    HStack {
                        Text(L10n.main.settings.featureAnnouncement.title).foregroundStyle(.primary)
                        Spacer()
                        if container.session.hasUnreadFeatureAnnouncements {
                            Text(N("settings.about.new")).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Theme.primary).foregroundStyle(.white).clipShape(Capsule())
                        }
                    }
                }
                Link(L10n.main.settings.privacyPolicy, destination: Brand.privacyPolicyURL)
                if let support = Brand.supportURL { Link(L10n.main.settings.support.button.title, destination: support) }
            }
            Section {
                Button {
                    versionTaps += 1
                    if versionTaps >= 10 {
                        container.session.settings.showTroubleshooting = true
                        unlockMessage = L10n.main.settings.troubleshootingUnlockedPopUp
                    } else if versionTaps >= 4 {
                        unlockMessage = L10n.main.settings.troubleshootingProgressPopUp(remainingTaps: 10 - versionTaps)
                    }
                } label: {
                    LabeledContent(L10n.main.settings.list.version, value: "\(BuildInfo.version) (\(BuildInfo.buildNumber))").foregroundStyle(.primary)
                }
                LabeledContent(N("settings.about.linphone"), value: PIL.shared?.linphoneVersion ?? N("settings.about.notStarted"))
            } footer: {
                if let unlockMessage { Text(unlockMessage) }
            }
        }
        .navigationTitle(L10n.main.settings.subPage.aboutTheApp.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAnnouncements) {
            PortalWebView(page: .featureAnnouncements) { container.session.markFeatureAnnouncementsRead() }
        }
    }
}
