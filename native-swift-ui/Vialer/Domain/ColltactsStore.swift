import Foundation
import Observation
import Contacts

enum ContactsPermission { case notDetermined, granted, limited, denied }

/// Device contacts, shared contacts and colleagues.
@MainActor
@Observable
final class ColltactsStore {
    private(set) var contacts: [DeviceContact] = []
    private(set) var contactsPermission: ContactsPermission = .notDetermined
    private(set) var isLoadingContacts = false

    private(set) var sharedContacts: [SharedContact]
    private(set) var isLoadingShared = false

    private(set) var colleagues: [Colleague]
    private(set) var isLoadingColleagues = false

    private weak var session: SessionManager?
    private weak var presence: PresenceManager?
    private let sharedAPI = SharedContactsAPI()
    private let voipgrid = VoipgridAPI()
    private let store = LocalStore.shared
    private let contactStore = CNContactStore()
    private var changeObserver: NSObjectProtocol?

    init() {
        sharedContacts = store.get(.sharedContacts) ?? []
        colleagues = store.get(.colleagues) ?? []
    }

    func bind(session: SessionManager, presence: PresenceManager) {
        self.session = session
        self.presence = presence
        presence.onUnknownColleague = { [weak self] in Task { await self?.loadColleagues() } }
        changeObserver = NotificationCenter.default.addObserver(
            forName: .CNContactStoreDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.loadContacts() }
        }
    }

    /// Debug-only sample data for simulator previews.
    func installPreviewData() {
        colleagues = [
            Colleague(id: "c1", name: "Alex Bakker", context: [], status: .available, destination: ColleagueDestination(number: "202", type: .app)),
            Colleague(id: "c2", name: "Sam de Vries", context: [.inCall], status: .busy, destination: ColleagueDestination(number: "203", type: .voipAccount)),
            Colleague(id: "c3", name: "Chris Jansen", context: [], status: .doNotDisturb, destination: ColleagueDestination(number: "204", type: .app)),
            Colleague(id: "c4", name: "Noor Visser", context: [], status: .offline, destination: ColleagueDestination(number: "205", type: .none)),
            Colleague(id: "c5", name: "Reception", isUnconnectedVoipAccount: true, unconnectedNumber: "200"),
        ]
        sharedContacts = [
            SharedContact(id: "s1", givenName: "Acme", familyName: "Support", companyName: "Acme B.V.", phoneNumbers: [SharedContactPhoneNumber(phoneNumberFlat: "+31201234567")]),
            SharedContact(id: "s2", givenName: "Bob", familyName: "Builder", companyName: nil, phoneNumbers: [SharedContactPhoneNumber(phoneNumberFlat: "+31612345678")]),
        ]
    }

    // MARK: Device contacts

    func refreshContactsPermission() {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: contactsPermission = .granted
        case .limited: contactsPermission = .limited
        case .denied, .restricted: contactsPermission = .denied
        default: contactsPermission = .notDetermined
        }
    }

    func requestContactsPermission() async -> Bool {
        let granted = (try? await contactStore.requestAccess(for: .contacts)) ?? false
        refreshContactsPermission()
        if granted { await loadContacts() }
        return granted
    }

    func loadContacts() async {
        refreshContactsPermission()
        guard contactsPermission == .granted || contactsPermission == .limited else {
            contacts = []
            return
        }
        isLoadingContacts = true
        defer { isLoadingContacts = false }
        let sortOrder = CNContactsUserDefaults.shared().sortOrder
        let loaded: [DeviceContact] = await Task.detached(priority: .userInitiated) {
            let keys: [CNKeyDescriptor] = [
                CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey,
                CNContactOrganizationNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
                CNContactThumbnailImageDataKey,
            ] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = sortOrder
            var result: [DeviceContact] = []
            do {
                try CNContactStore().enumerateContacts(with: request) { contact, _ in
                    let phones = contact.phoneNumbers.map {
                        DeviceContact.LabeledValue(
                            label: CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: $0.label ?? ""),
                            value: $0.value.stringValue
                        )
                    }
                    guard !phones.isEmpty else { return }
                    let emails = contact.emailAddresses.map {
                        DeviceContact.LabeledValue(
                            label: CNLabeledValue<NSString>.localizedString(forLabel: $0.label ?? ""),
                            value: $0.value as String
                        )
                    }
                    result.append(DeviceContact(
                        id: contact.identifier,
                        givenName: contact.givenName,
                        familyName: contact.familyName,
                        company: contact.organizationName,
                        phoneNumbers: phones,
                        emails: emails,
                        thumbnail: contact.thumbnailImageData
                    ))
                }
            } catch {
                AppLog.warning("Failed to load contacts: \(error)")
            }
            return result.filter { !$0.displayName.isEmpty }
        }.value
        contacts = loaded
    }

    /// Any colltact (device contact, shared contact or colleague) with this number.
    func colltact(matching number: String) -> Colltact? {
        if let contact = contact(matching: number) { return .contact(contact) }
        let digits = number.normalizedDigits
        if let shared = sharedContacts.first(where: { $0.phoneNumbers.contains { $0.phoneNumberFlat.normalizedDigits == digits } }) {
            return .shared(shared)
        }
        if number.isInternalNumber, let colleague = colleaguesWithPresence.first(where: { $0.number == number }) {
            return .colleague(colleague)
        }
        return nil
    }

    func contact(matching number: String) -> DeviceContact? {
        let digits = number.normalizedDigits
        guard digits.count >= 6 else { return nil }
        return contacts.first { contact in
            contact.phoneNumbers.contains { $0.value.normalizedDigits.hasSuffix(digits.suffix(9)) }
        }
    }

    // MARK: Shared contacts

    func loadSharedContacts() async {
        guard let clientUuid = session?.user?.client.uuid else { return }
        isLoadingShared = true
        defer { isLoadingShared = false }
        do {
            sharedContacts = try await sharedAPI.list(clientUuid: clientUuid).sorted {
                $0.simpleDisplayName.localizedCaseInsensitiveCompare($1.simpleDisplayName) == .orderedAscending
            }
            store.set(sharedContacts, for: .sharedContacts)
        } catch {
            AppLog.warning("Failed to load shared contacts: \(error)")
        }
    }

    func save(_ contact: SharedContact) async -> Bool {
        guard let clientUuid = session?.user?.client.uuid else { return false }
        let ok = contact.id == nil
            ? await sharedAPI.create(clientUuid: clientUuid, contact: contact)
            : await sharedAPI.update(clientUuid: clientUuid, contact: contact)
        if ok { await loadSharedContacts() }
        return ok
    }

    func delete(_ contact: SharedContact) async -> Bool {
        guard let clientUuid = session?.user?.client.uuid, let id = contact.id else { return false }
        let ok = await sharedAPI.delete(clientUuid: clientUuid, id: id)
        if ok { await loadSharedContacts() }
        return ok
    }

    // MARK: Colleagues

    var shouldShowColleagues: Bool {
        guard let user = session?.user else { return false }
        return user.hasPermission(.canViewColleagues) || user.hasPermission(.canViewVoipAccounts)
    }

    func loadColleagues() async {
        guard let user = session?.user, shouldShowColleagues else { return }
        isLoadingColleagues = true
        defer { isLoadingColleagues = false }
        do {
            colleagues = try await voipgrid.getColleagues(user: user)
            store.set(colleagues, for: .colleagues)
        } catch {
            AppLog.warning("Failed to load colleagues: \(error)")
        }
    }

    /// Colleagues with live presence merged in.
    var colleaguesWithPresence: [Colleague] {
        let presence = presence?.presence ?? [:]
        return colleagues.map { colleague in
            guard !colleague.isUnconnectedVoipAccount, let p = presence[colleague.id] else { return colleague }
            var c = colleague
            c.status = p.status
            c.context = p.context
            c.destination = p.destination
            return c
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

extension String {
    var normalizedDigits: String {
        let allowed = Set("0123456789+")
        var result = String(filter { allowed.contains($0) })
        if result.hasPrefix("+") { result = "0" + result.dropFirst(3) }
        if result.hasPrefix("00") { result = "0" + result.dropFirst(4) }
        return result
    }
}
