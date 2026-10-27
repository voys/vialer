import SwiftUI

struct ClientSettingsView: View {
    @Environment(AppContainer.self) private var container
    @State private var portalPage: PortalPage?
    @State private var showRedirect = false

    private var user: User? { container.session.user }
    private var portal: L10n.main.settings.list.portalLinks.Type { L10n.main.settings.list.portalLinks.self }

    static func isAvailable(for user: User) -> Bool {
        [.canChangeTemporaryRedirect, .canSeeClientCalls, .canViewDialPlans, .canChangeOpeningHours, .canViewStats]
            .contains { user.hasPermission($0) }
    }

    var body: some View {
        List {
            if user?.hasPermission(.canChangeTemporaryRedirect) == true {
                Section(N("settings.client.availability")) {
                    Button { showRedirect = true } label: {
                        LabeledContent(L10n.main.temporaryRedirect.title, value: redirectValue).foregroundStyle(.primary)
                    }
                    .disabled(!container.connectivity.isConnected || container.session.isRateLimited)
                }
            }
            Section(portal.title) {
                if user?.hasPermission(.canSeeClientCalls) == true {
                    portalLink(portal.calls.title, .calls)
                }
                if user?.hasPermission(.canViewDialPlans) == true {
                    portalLink(portal.dialplan.title, .dialPlan)
                }
                if user?.hasPermission(.canChangeOpeningHours) == true {
                    portalLink(portal.openingHours.title, user?.client.openingHoursModuleId != nil ? .openingHoursBasicEdit : .openingHoursBasicList)
                }
                if user?.hasPermission(.canViewStats) == true {
                    portalLink(portal.stats.title, .stats)
                }
            }
        }
        .navigationTitle(L10n.main.settings.subPage.client.title(client: user?.client.name ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $portalPage) { PortalWebView(page: $0) }
        .sheet(isPresented: $showRedirect) { TemporaryRedirectView() }
    }

    private var redirectValue: String {
        guard let redirect = user?.client.currentTemporaryRedirect else { return L10n.generic.off }
        return N("settings.client.redirectUntil", ["date": redirect.endsAt.formatted(date: .abbreviated, time: .shortened)])
    }

    private func portalLink(_ title: String, _ page: PortalPage) -> some View {
        Button { portalPage = page } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right.square").foregroundStyle(Theme.grey4)
            }
        }
    }
}

extension PortalPage: Identifiable {
    var id: String { title + path(for: User.placeholder) }
}

extension User {
    /// Only used to derive stable identifiers for portal pages.
    static let placeholder = User(
        uuid: "", email: "", firstName: "", preposition: "", lastName: "", token: "",
        client: Client(id: 0, uuid: "", name: "", url: "", voip: .fallback)
    )
}

struct TemporaryRedirectView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var voicemail: VoicemailAccount?
    @State private var until = Date().addingTimeInterval(3600)
    @State private var isSaving = false
    @State private var error: String?
    @State private var showAddVoicemail = false

    private var session: SessionManager { container.session }
    private var current: TemporaryRedirect? { session.user?.client.currentTemporaryRedirect }
    private var voicemails: [VoicemailAccount] { session.user?.client.voicemailAccounts ?? [] }
    private var strings: L10n.main.temporaryRedirect.Type { L10n.main.temporaryRedirect.self }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(current == nil ? strings.actions.setupRedirect.description : N("temporaryRedirect.explanation.ongoing"))
                        .foregroundStyle(Theme.infoText)
                }
                Section(strings.dropdown.title) {
                    if voicemails.isEmpty {
                        Text(strings.dropdown.noVoicemails.item).foregroundStyle(Theme.infoText)
                        Button(N("temporaryRedirect.addVoicemail")) { showAddVoicemail = true }
                    } else {
                        Picker(strings.dropdown.title, selection: $voicemail) {
                            ForEach(voicemails) { Text($0.displayName).tag(Optional($0)) }
                        }
                    }
                }
                Section(strings.until.title) {
                    DatePicker(strings.until.title, selection: $until, in: Date()...Date().addingTimeInterval(365 * 24 * 3600), displayedComponents: [.date, .hourAndMinute])
                }
                if let error { Section { Text(error).foregroundStyle(Theme.red) } }
                Section {
                    Button(current == nil ? strings.actions.startRedirect.label : strings.actions.changeRedirect.label) { Task { await save() } }
                        .disabled(voicemail == nil || isSaving)
                    if current != nil {
                        Button(strings.actions.stopRedirect.label, role: .destructive) { Task { await stop() } }.disabled(isSaving)
                    }
                } footer: {
                    Text(current == nil ? "" : strings.actions.stopRedirect.description)
                }
            }
            .navigationTitle(strings.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.generic.button.cancel) { dismiss() } } }
            .onAppear {
                if let current {
                    voicemail = current.voicemail
                    until = current.endsAt
                }
                if voicemail == nil { voicemail = voicemails.first }
            }
            .sheet(isPresented: $showAddVoicemail) {
                PortalWebView(page: .addVoicemail) {
                    Task {
                        await session.refreshVoicemailAccounts()
                        if voicemail == nil { voicemail = voicemails.first }
                    }
                }
            }
        }
    }

    private func save() async {
        guard let voicemail else { return }
        if until < Date() {
            error = strings.until.error.timeInPast
            return
        }
        isSaving = true
        defer { isSaving = false }
        let redirect = TemporaryRedirect(id: current?.id, endsAt: until, voicemail: voicemail)
        if await session.setTemporaryRedirect(redirect) {
            await container.notices.check()
            dismiss()
        } else {
            error = N("temporaryRedirect.error.set")
        }
    }

    private func stop() async {
        isSaving = true
        defer { isSaving = false }
        if await session.cancelTemporaryRedirect() {
            await container.notices.check()
            dismiss()
        } else {
            error = N("temporaryRedirect.error.stop")
        }
    }
}
