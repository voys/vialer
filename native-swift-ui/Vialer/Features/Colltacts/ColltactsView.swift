import SwiftUI
import Contacts
import ContactsUI
import UIKit

enum ColltactTab: String, CaseIterable, Identifiable, Codable {
    case contacts, shared, colleagues
    var id: String { rawValue }

    var title: String {
        switch self {
        case .contacts: return L10n.main.contacts.tabBar.contactsTabTitle
        case .shared: return L10n.main.contacts.tabBar.sharedTabTitle
        case .colleagues: return L10n.main.contacts.tabBar.colleaguesTabTitle
        }
    }
}

struct ColltactsView: View {
    @Environment(AppContainer.self) private var container
    @State private var tab: ColltactTab = LocalStore.shared.get(.currentColltactTab) ?? .contacts
    @State private var search = ""
    @State private var showAddShared = false

    private var store: ColltactsStore { container.colltacts }
    private var strings: L10n.main.contacts.Type { L10n.main.contacts.self }

    var body: some View {
        @Bindable var session = container.session
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    BannerSection()
                    PickerRow {
                        Picker(strings.title, selection: $tab) {
                            ForEach(ColltactTab.allCases.filter { $0 != .colleagues || store.shouldShowColleagues }) {
                                Text($0.title).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    switch tab {
                    case .contacts: contactsContent
                    case .shared: sharedContent
                    case .colleagues: colleaguesContent
                    }
                }
                .listStyle(.plain)
                .contentMargins(.top, 0, for: .scrollContent)
                .overlay(alignment: .trailing) {
                    let keys = sectionKeys(for: currentItems)
                    if keys.count > 3 {
                        SectionIndex(keys: keys, proxy: proxy).padding(.trailing, 2)
                    }
                }
                .refreshable {
                    switch tab {
                    case .contacts: await store.loadContacts()
                    case .shared: await store.loadSharedContacts()
                    case .colleagues:
                        await store.loadColleagues()
                        container.presence.refresh()
                    }
                }
            }
            .navigationTitle(strings.title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: strings.searchBar.placeholder)
            .toolbar {
                if tab == .shared {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showAddShared = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel(strings.list.addSharedContact.title)
                    }
                }
                if tab == .colleagues {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Toggle(L10n.main.colleagues.toggle, isOn: $session.settings.showOnlineColleaguesOnly)
                        } label: {
                            Image(systemName: session.settings.showOnlineColleaguesOnly
                                  ? "line.3.horizontal.decrease.circle.fill"
                                  : "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityLabel(L10n.main.colleagues.toggle)
                    }
                }
            }
            .sheet(isPresented: $showAddShared) { SharedContactFormView(contact: SharedContact()) }
            .onAppear { store.refreshContactsPermission() }
            .onChange(of: tab) { _, value in
                LocalStore.shared.set(value, for: .currentColltactTab)
                Metrics.track("colltacts-tab-selected", ["tab": value.rawValue])
            }
            .navigationDestination(for: Colltact.self) { ColltactDetailView(colltact: $0) }
        }
    }

    // MARK: Items per tab

    private var filteredContacts: [DeviceContact] {
        store.contacts.filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) || $0.phoneNumbers.contains { $0.value.contains(search) } }
    }

    private var filteredShared: [SharedContact] {
        store.sharedContacts.filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) || $0.phoneNumbers.contains { $0.phoneNumberFlat.contains(search) } }
    }

    private var filteredColleagues: [Colleague] {
        let onlineOnly = container.session.settings.showOnlineColleaguesOnly
        return store.colleaguesWithPresence.filter {
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || ($0.number ?? "").contains(search))
            && (!onlineOnly || $0.isOnline)
        }
    }

    private var currentItems: [Colltact] {
        switch tab {
        case .contacts: return filteredContacts.map(Colltact.contact)
        case .shared: return filteredShared.map(Colltact.shared)
        case .colleagues: return filteredColleagues.map(Colltact.colleague)
        }
    }

    // MARK: Contacts

    @ViewBuilder
    private var contactsContent: some View {
        let noPermission = strings.list.noPermission.self
        switch store.contactsPermission {
        case .denied:
            PlaceholderRow {
                PlaceholderView(systemImage: "person.crop.circle.badge.exclamationmark", title: noPermission.title(appName: Brand.appName),
                                message: noPermission.permanentDescription(appName: Brand.appName),
                                buttonTitle: noPermission.buttonOpenSettings) { openSettings() }
            }
        case .notDetermined:
            PlaceholderRow {
                PlaceholderView(systemImage: "person.crop.circle", title: noPermission.title(appName: Brand.appName),
                                message: noPermission.description(appName: Brand.appName),
                                buttonTitle: noPermission.buttonPermission) { Task { await store.requestContactsPermission() } }
            }
        default:
            let items = filteredContacts
            if store.isLoadingContacts && store.contacts.isEmpty {
                PlaceholderRow { ProgressView(strings.list.loadingContacts.title) }
            } else if items.isEmpty {
                PlaceholderRow {
                    if search.isEmpty {
                        PlaceholderView(systemImage: "person.crop.circle", title: strings.list.empty.title,
                                        message: strings.list.empty.description(appName: Brand.appName))
                    } else {
                        PlaceholderView(systemImage: "person.crop.circle", title: L10n.main.colltacts.noResults.title,
                                        message: L10n.main.colltacts.noResults.contacts(number: search))
                    }
                }
            } else {
                if store.contactsPermission == .limited {
                    Section {
                        HStack {
                            Text(L10n.main.colltacts.contacts.limitedPermission.description(appName: Brand.appName)).font(.caption)
                            Spacer()
                            Button(L10n.main.colltacts.contacts.limitedPermission.button) { openSettings() }.font(.caption)
                        }
                        .bannerCard(Theme.primary.opacity(0.12))
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                sections(items.map(Colltact.contact))
            }
        }
    }

    // MARK: Shared

    @ViewBuilder
    private var sharedContent: some View {
        let items = filteredShared
        if store.isLoadingShared && store.sharedContacts.isEmpty {
            PlaceholderRow { ProgressView(strings.list.loadingSharedContacts.title) }
        } else if items.isEmpty {
            PlaceholderRow {
                if search.isEmpty {
                    PlaceholderView(systemImage: "person.2.crop.square.stack", title: strings.list.emptySharedContacts.title,
                                    message: strings.list.emptySharedContacts.description(appName: Brand.appName),
                                    buttonTitle: strings.list.createSharedContactButton.title) { showAddShared = true }
                } else {
                    PlaceholderView(systemImage: "person.2.crop.square.stack", title: L10n.main.colltacts.noResults.title,
                                    message: L10n.main.colltacts.noResults.sharedContacts(term: search))
                }
            }
        } else {
            sections(items.map(Colltact.shared))
        }
    }

    // MARK: Colleagues

    @ViewBuilder
    private var colleaguesContent: some View {
        let onlineOnly = container.session.settings.showOnlineColleaguesOnly
        let items = filteredColleagues
        if !container.presence.isConnected {
            Section {
                Text(L10n.main.colleagues.websocketUnreachableNotice.content(appName: Brand.appName))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        if store.isLoadingColleagues && store.colleagues.isEmpty {
            PlaceholderRow { ProgressView(strings.list.loadingColleagues.title) }
        } else if items.isEmpty {
            PlaceholderRow {
                if !search.isEmpty {
                    PlaceholderView(systemImage: "person.3", title: L10n.main.colltacts.noResults.title,
                                    message: L10n.main.colltacts.noResults.colleagues(number: search))
                } else if onlineOnly {
                    PlaceholderView(systemImage: "person.3", title: L10n.main.colltacts.noOnline.title,
                                    message: L10n.main.colltacts.noOnline.subtitle)
                } else {
                    PlaceholderView(systemImage: "person.3", title: N("colltacts.colleagues.empty"))
                }
            }
        } else {
            sections(items.map(Colltact.colleague))
        }
    }

    // MARK: Sections

    private func sectionKeys(for items: [Colltact]) -> [String] {
        grouped(items).keys.sorted { a, b in
            if a == "#" { return false }
            if b == "#" { return true }
            return a < b
        }
    }

    private func grouped(_ items: [Colltact]) -> [String: [Colltact]] {
        Dictionary(grouping: items) { item -> String in
            let first = item.displayName.folding(options: .diacriticInsensitive, locale: nil).uppercased().first
            return first.map { $0.isLetter ? String($0) : "#" } ?? "#"
        }
    }

    private func sections(_ items: [Colltact]) -> some View {
        let groups = grouped(items)
        return ForEach(sectionKeys(for: items), id: \.self) { key in
            Section(key) {
                ForEach(groups[key] ?? []) { item in
                    NavigationLink(value: item) { ColltactRow(colltact: item) }
                }
            }
            .id(key)
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

struct ColltactRow: View {
    let colltact: Colltact

    var body: some View {
        HStack(spacing: 12) {
            switch colltact {
            case .contact(let c):
                AvatarView(name: c.displayName, image: c.thumbnail)
            case .shared(let s):
                AvatarView(name: s.simpleDisplayName)
            case .colleague(let c):
                AvatarView(name: c.name, statusColor: c.statusColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(colltact.displayName).lineLimit(1)
                if case .colleague(let c) = colltact {
                    Text(c.statusText).font(.caption).foregroundStyle(Theme.infoText)
                } else if let number = colltact.primaryNumber {
                    Text(number).font(.caption).foregroundStyle(Theme.infoText)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct ColltactDetailView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    let colltact: Colltact
    @State private var showEdit = false
    @State private var showNativeEditor = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    switch colltact {
                    case .contact(let c): AvatarView(name: c.displayName, image: c.thumbnail, size: 96)
                    case .shared(let s): AvatarView(name: s.simpleDisplayName, size: 96)
                    case .colleague(let c): AvatarView(name: c.name, size: 96, statusColor: c.statusColor)
                    }
                    Text(colltact.displayName).font(.title2.bold()).multilineTextAlignment(.center)
                    if case .colleague(let c) = colltact {
                        Text(c.statusText).foregroundStyle(Theme.infoText)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section(N("colltacts.details.phoneNumbers")) {
                ForEach(numbers, id: \.value) { entry in
                    Button {
                        container.call(entry.value)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(entry.value).foregroundStyle(.primary)
                                if !entry.label.isEmpty { Text(entry.label).font(.caption).foregroundStyle(Theme.infoText) }
                            }
                            Spacer()
                            Image(systemName: "phone.fill").foregroundStyle(Theme.green)
                        }
                    }
                }
            }

            if case .contact(let c) = colltact, !c.emails.isEmpty {
                Section(N("colltacts.details.email")) {
                    ForEach(c.emails, id: \.value) { email in
                        Link(destination: URL(string: "mailto:\(email.value)")!) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(email.value).foregroundStyle(.primary)
                                    if !email.label.isEmpty { Text(email.label).font(.caption).foregroundStyle(Theme.infoText) }
                                }
                                Spacer()
                                Image(systemName: "envelope").foregroundStyle(Theme.grey4)
                            }
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                switch colltact {
                case .contact: Button(L10n.main.contacts.edit) { showNativeEditor = true }
                case .shared: Button(L10n.main.contacts.edit) { showEdit = true }
                case .colleague: EmptyView()
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if case .shared(let s) = colltact { SharedContactFormView(contact: s) }
        }
        .sheet(isPresented: $showNativeEditor) {
            if case .contact(let c) = colltact { NativeContactEditor(identifier: c.id) }
        }
    }

    private var numbers: [DeviceContact.LabeledValue] {
        switch colltact {
        case .contact(let c): return c.phoneNumbers
        case .shared(let s): return s.phoneNumbers.map { .init(label: "", value: $0.phoneNumberPretty ?? $0.phoneNumberFlat) }
        case .colleague(let c): return c.number.map { [.init(label: N("colltacts.details.internalNumber"), value: $0)] } ?? []
        }
    }
}

/// Picker used by the transfer screen.
struct ColltactPickerView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    var onPick: (String) -> Void

    private var items: [Colltact] {
        let contacts = container.colltacts.contacts.map(Colltact.contact)
        let shared = container.colltacts.sharedContacts.map(Colltact.shared)
        let colleagues = container.colltacts.colleaguesWithPresence.filter { $0.number != nil }.map(Colltact.colleague)
        return (colleagues + contacts + shared)
            .filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List(items) { item in
                Button {
                    if let number = item.primaryNumber { onPick(number) }
                } label: { ColltactRow(colltact: item) }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .searchable(text: $search, prompt: L10n.main.contacts.searchBar.placeholder)
            .navigationTitle(N("colltacts.picker.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.generic.button.cancel) { dismiss() } } }
        }
    }
}

struct SharedContactFormView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State var contact: SharedContact
    @State private var numbers: [String] = []
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmDelete = false

    private var form: L10n.main.contacts.sharedContacts.form.Type { L10n.main.contacts.sharedContacts.form.self }

    var body: some View {
        NavigationStack {
            Form {
                Section(N("colltacts.form.name")) {
                    TextField(form.firstNameHintText, text: Binding(get: { contact.givenName ?? "" }, set: { contact.givenName = $0 }))
                    TextField(form.lastNameHintText, text: Binding(get: { contact.familyName ?? "" }, set: { contact.familyName = $0 }))
                    TextField(form.companyHintText, text: Binding(get: { contact.companyName ?? "" }, set: { contact.companyName = $0 }))
                }
                Section(N("colltacts.form.phoneNumbers")) {
                    ForEach(numbers.indices, id: \.self) { i in
                        HStack {
                            TextField(form.phoneNumberHintText, text: $numbers[i]).keyboardType(.phonePad)
                            if numbers.count > 1 {
                                Button { numbers.remove(at: i) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(Theme.red) }
                            }
                        }
                    }
                    Button { numbers.append("") } label: { Label(form.addPhoneNumberButtonTitle, systemImage: "plus.circle") }
                }
                if let error { Section { Text(error).foregroundStyle(Theme.red) } }
                if contact.id != nil {
                    Section {
                        Button(form.deleteContactButtonTitle, role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(contact.id == nil ? L10n.main.contacts.list.addSharedContact.title : L10n.main.contacts.list.editSharedContact.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(form.cancelButtonTitle) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(form.saveContactButtonTitle) { Task { await save() } }.disabled(isSaving || !isValid)
                }
            }
            .confirmationDialog(form.confirmationDialog.deleteContactDialogTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(form.confirmationDialog.deleteContactButtonTitle, role: .destructive) {
                    Task {
                        if await container.colltacts.delete(contact) { dismiss() } else { error = form.genericError }
                    }
                }
            } message: {
                Text(form.confirmationDialog.deleteContactDialogContent(contactName: contact.simpleDisplayName))
            }
            .onAppear {
                numbers = contact.phoneNumbers.map(\.phoneNumberFlat)
                if numbers.isEmpty { numbers = [""] }
            }
        }
    }

    private var isValid: Bool {
        let hasName = !(contact.givenName ?? "").isEmpty || !(contact.familyName ?? "").isEmpty || !(contact.companyName ?? "").isEmpty
        return hasName && numbers.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var toSave = contact
        toSave.phoneNumbers = numbers
            .map { $0.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
            .map { SharedContactPhoneNumber(phoneNumberFlat: $0) }
        if await container.colltacts.save(toSave) {
            dismiss()
        } else {
            error = form.genericError
        }
    }
}

/// Opens the system contact editor for a device contact.
struct NativeContactEditor: UIViewControllerRepresentable {
    let identifier: String

    func makeUIViewController(context: Context) -> UINavigationController {
        let store = CNContactStore()
        let keys = [CNContactViewController.descriptorForRequiredKeys()]
        let controller: UIViewController
        if let contact = try? store.unifiedContact(withIdentifier: identifier, keysToFetch: keys) {
            let vc = CNContactViewController(for: contact)
            vc.allowsEditing = true
            vc.allowsActions = false
            controller = vc
        } else {
            controller = UIViewController()
        }
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
