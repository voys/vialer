import SwiftUI
import UIKit

struct RecentsView: View {
    @Environment(AppContainer.self) private var container
    @State private var scope: RecentsScope = .personal
    @State private var copied = false
    @State private var detail: CallRecord?
    @State private var contactToView: Colltact?
    @State private var sharedContactDraft: SharedContact?

    private var recents: RecentsStore { container.recents }
    private var showClientTab: Bool {
        container.session.settings.showClientCalls && (container.session.user?.hasPermission(.canSeeClientCalls) ?? false)
    }

    var body: some View {
        @Bindable var recents = recents
        NavigationStack {
            List {
                BannerSection()
                PickerRow {
                    VStack(spacing: 8) {
                        Picker(L10n.main.recent.title, selection: $recents.onlyMissed) {
                            Text(L10n.main.recent.tabs.all).tag(false)
                            Text(L10n.main.recent.onlyShowMissedCalls).tag(true)
                        }
                        .pickerStyle(.segmented)
                        if showClientTab {
                            Picker(L10n.main.recent.title, selection: $scope) {
                                ForEach(RecentsScope.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }
                content
            }
            .listStyle(.plain)
            .contentMargins(.top, 0, for: .scrollContent)
            .refreshable { await recents.refresh(scope: scope) }
            .navigationTitle(L10n.main.recent.title)
            .navigationBarTitleDisplayMode(.inline)
            .task { if recents.records[.personal]?.isEmpty ?? true { await recents.loadMore(scope: .personal) } }
            .onChange(of: scope) { _, value in
                if recents.records[value]?.isEmpty ?? true { Task { await recents.loadMore(scope: value) } }
            }
            .onChange(of: container.calls.phase) { _, phase in
                if phase == .ended {
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        await recents.refresh(scope: scope)
                    }
                }
            }
            .sheet(item: $detail) { record in CallDetailsSheet(record: record) }
            .sheet(item: $contactToView) { colltact in
                NavigationStack { ColltactDetailView(colltact: colltact) }
            }
            .sheet(item: $sharedContactDraft) { draft in SharedContactFormView(contact: draft) }
            .overlay(alignment: .bottom) {
                if copied {
                    Text(L10n.main.recent.snackBar.copied).padding(8).background(.ultraThinMaterial).clipShape(Capsule()).padding(.bottom, 60)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let records = recents.records[scope] ?? []
        let grouped = Dictionary(grouping: records) { Calendar.current.startOfDay(for: $0.date) }
        let days = grouped.keys.sorted(by: >)
        if records.isEmpty && recents.isLoading {
            PlaceholderRow { ProgressView(L10n.main.recent.list.loading.title) }
        } else if records.isEmpty {
            PlaceholderRow {
                PlaceholderView(systemImage: "clock.arrow.circlepath", title: L10n.main.recent.list.empty.title,
                                message: recents.onlyMissed ? N("recents.empty.missed") : L10n.main.recent.list.empty.description)
            }
        } else {
            ForEach(days, id: \.self) { day in
                Section(day.recentsDayLabel) {
                    ForEach(grouped[day] ?? []) { record in
                        RecentCallRow(record: record, scope: scope)
                            .contentShape(Rectangle())
                            .onTapGesture { container.call(record.thirdPartyNumber) }
                            .contextMenu { menu(for: record) }
                            .onAppear {
                                if record.id == records.last?.id { Task { await recents.loadMore(scope: scope) } }
                            }
                    }
                }
            }
            if recents.isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
    }

    @ViewBuilder
    private func menu(for record: CallRecord) -> some View {
        let menu = L10n.main.recent.list.item.popupMenu.self
        Button { detail = record } label: { Label(menu.callDetails.title, systemImage: "info.circle") }
        Button {
            UIPasteboard.general.string = record.thirdPartyNumber
            copied = true
            Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
        } label: { Label(menu.copy, systemImage: "doc.on.doc") }
        Button { container.call(record.thirdPartyNumber) } label: { Label(menu.call, systemImage: "phone") }
        if let colltact = container.colltacts.colltact(matching: record.thirdPartyNumber) {
            Button { contactToView = colltact } label: { Label(menu.viewContact, systemImage: "person.crop.circle") }
        } else if !record.isInternal {
            Button {
                let name = record.thirdPartyName ?? ""
                let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
                sharedContactDraft = SharedContact(
                    givenName: parts.first ?? "",
                    familyName: parts.count > 1 ? parts[1] : "",
                    phoneNumbers: [SharedContactPhoneNumber(phoneNumberFlat: record.thirdPartyNumber)]
                )
            } label: { Label(menu.addSharedContact, systemImage: "person.badge.plus") }
        }
    }
}

struct RecentCallRow: View {
    @Environment(AppContainer.self) private var container
    let record: CallRecord
    let scope: RecentsScope

    private var contactName: String? {
        container.colltacts.contact(matching: record.thirdPartyNumber)?.displayName
    }

    /// The network's caller name is only shown for colleague calls unless the setting is on.
    private var callerName: String? {
        if record.isInternal || container.session.settings.alwaysShowCallerNameInRecents { return record.thirdPartyName }
        return nil
    }

    private var title: String {
        let name = contactName ?? callerName
        if let name, !name.isEmpty {
            return record.isInternal ? N("recents.internalPrefix", ["name": name]) : name
        }
        return record.thirdPartyNumber
    }

    private var subtitle: String {
        if scope == .client {
            return "\(record.caller.label) → \(record.destination.label)"
        }
        return (contactName != nil || callerName != nil) ? record.thirdPartyNumber : ""
    }

    private var icon: (name: String, color: Color) {
        if record.isIncomingAndAnsweredElsewhere { return ("phone.arrow.down.left", Theme.answeredElsewhere) }
        if record.wasMissed && record.isInbound { return ("phone.arrow.down.left", Theme.red) }
        if record.isInbound { return ("phone.arrow.down.left", Theme.green) }
        return ("phone.arrow.up.right", Theme.grey4)
    }

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: contactName ?? callerName ?? "#", size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(record.wasMissed && record.isInbound ? Theme.red : .primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: icon.name).foregroundStyle(icon.color).font(.caption)
                    if !subtitle.isEmpty { Text(subtitle).lineLimit(1) }
                    if record.summary != nil { Image(systemName: "sparkles").font(.caption).foregroundStyle(Theme.primary) }
                }
                .font(.subheadline)
                .foregroundStyle(Theme.infoText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(record.date.formatted(date: .omitted, time: .shortened))
                if record.answered { Text(record.duration.shortDuration).foregroundStyle(Theme.infoText) }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [title]
        if !subtitle.isEmpty { parts.append(subtitle) }
        if record.isIncomingAndAnsweredElsewhere {
            parts.append(N("recents.screenReader.answeredElsewhere"))
        } else if record.wasMissed && record.isInbound {
            parts.append(N("recents.details.missed"))
        } else {
            parts.append(record.isInbound ? N("recents.details.incoming") : N("recents.details.outgoing"))
        }
        parts.append(record.date.formatted(date: .abbreviated, time: .shortened))
        if record.answered { parts.append(record.duration.shortDuration) }
        return parts.joined(separator: ", ")
    }
}

struct CallDetailsSheet: View {
    @Environment(AppContainer.self) private var container
    let record: CallRecord
    @Environment(\.dismiss) private var dismiss
    @State private var showIntelligence = false

    private var hasSummaryModule: Bool {
        container.session.user?.client.enabledModules.contains(.summarizeCallTranscriptions) ?? false
    }

    var body: some View {
        let menu = L10n.main.recent.list.item.popupMenu.self
        NavigationStack {
            List {
                Section(menu.callDetails.callWith(name: record.displayLabel)) {
                    LabeledContent(N("recents.details.number"), value: record.thirdPartyNumber)
                    LabeledContent(N("recents.details.direction"), value: record.isInbound ? N("recents.details.incoming") : N("recents.details.outgoing"))
                    LabeledContent(N("recents.details.started"), value: record.date.formatted())
                    LabeledContent(N("recents.details.duration"), value: record.duration.shortDuration)
                    LabeledContent(N("recents.details.from"), value: record.caller.label)
                    LabeledContent(N("recents.details.to"), value: record.destination.label)
                }
                if let summary = record.summary, !summary.isEmpty {
                    Section(menu.aiCallSummary.title) {
                        Text(summary)
                        Button(N("recents.details.copySummary")) { UIPasteboard.general.string = summary }
                    }
                } else if !hasSummaryModule {
                    Section(menu.aiCallSummary.title) {
                        Text(menu.aiCallSummary.upsell).foregroundStyle(Theme.infoText)
                        Button(menu.aiCallSummary.enableButton(appName: Brand.appName)) { showIntelligence = true }
                    }
                } else {
                    Section(menu.aiCallSummary.title) {
                        Text(menu.aiCallSummary.doesNotExist).foregroundStyle(Theme.infoText)
                    }
                }
                Section { Text(menu.callDetails.callId(id: record.id)).font(.caption) }
            }
            .navigationTitle(menu.callDetails.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.generic.button.done) { dismiss() } } }
            .sheet(isPresented: $showIntelligence) { PortalWebView(page: .intelligence) }
        }
    }
}
