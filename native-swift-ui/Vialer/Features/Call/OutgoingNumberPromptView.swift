import SwiftUI

/// Asks which business number to show before an outgoing call. Mirrors the Flutter
/// `OutgoingNumberPrompt`: current number, the other numbers, suppress, and "don't ask again".
struct OutgoingNumberPromptView: View {
    @Environment(AppContainer.self) private var container
    let pending: PendingCall

    @State private var isUpdating = false
    @State private var failed = false
    @State private var dontShowAgain = false
    @State private var expanded = false

    private static let maxNumbersBeforeExpanding = 4
    private var session: SessionManager { container.session }
    private var current: OutgoingNumber { session.settings.outgoingNumber }
    private var others: [OutgoingNumber] {
        (session.user?.client.outgoingNumbers ?? []).filter { $0 != current }
    }
    private var strings: L10n.main.outgoingCLI.prompt.Type { L10n.main.outgoingCLI.prompt.self }

    var body: some View {
        NavigationStack {
            Group {
                if failed {
                    PlaceholderView(systemImage: "exclamationmark.triangle", title: strings.updatingNumber.error.title,
                                    message: strings.updatingNumber.error.description,
                                    buttonTitle: L10n.generic.button.tryAgain) { failed = false }
                } else {
                    list
                }
            }
            .navigationTitle(N("outgoingNumber.prompt.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.generic.button.cancel) { container.outgoingCalls.promptCancelled() }
                }
            }
            .disabled(isUpdating)
            .overlay { if isUpdating { ProgressView(strings.updatingNumber.title) } }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }

    private var list: some View {
        List {
            Section(strings.title) {
                EmptyView()
            }
            Section(strings.currentOutgoingNumber.label) {
                row(current, isCurrent: true)
            }
            Section(N("outgoingNumber.prompt.other")) {
                let visible = expanded || others.count <= Self.maxNumbersBeforeExpanding
                    ? others
                    : Array(others.prefix(Self.maxNumbersBeforeExpanding - 1))
                ForEach(visible, id: \.self) { row($0, isCurrent: false) }
                if !expanded, others.count > Self.maxNumbersBeforeExpanding {
                    Button(N("outgoingNumber.prompt.showAll", ["count": others.count])) { expanded = true }
                }
                if !current.isSuppressed {
                    row(.suppressed, isCurrent: false)
                }
            }
            Section {
                Toggle(strings.checkbox.label, isOn: $dontShowAgain)
            } footer: {
                Text(strings.checkbox.helpText)
            }
        }
    }

    private func row(_ number: OutgoingNumber, isCurrent: Bool) -> some View {
        Button {
            Task { await select(number) }
        } label: {
            HStack {
                Image(systemName: number.isSuppressed ? "eye.slash" : "phone")
                    .foregroundStyle(Theme.grey4)
                VStack(alignment: .leading) {
                    Text(number.isSuppressed ? strings.suppress.title : number.value).foregroundStyle(.primary)
                    if number.isSuppressed {
                        Text(strings.suppress.description).font(.caption).foregroundStyle(Theme.infoText)
                    } else if let d = number.description, !d.isEmpty {
                        Text(d).font(.caption).foregroundStyle(Theme.infoText)
                    }
                }
                Spacer()
                Image(systemName: isCurrent ? "phone.arrow.up.right.fill" : "arrow.right")
                    .foregroundStyle(isCurrent ? Theme.green : Theme.grey4)
            }
        }
    }

    private func select(_ number: OutgoingNumber) async {
        LocalStore.shared.setBool(dontShowAgain, for: .doNotShowOutgoingNumberSelector)
        if number == current {
            container.outgoingCalls.promptCompleted(pending)
            return
        }
        isUpdating = true
        let ok = await session.changeOutgoingNumber(number)
        isUpdating = false
        if ok {
            container.outgoingCalls.promptCompleted(pending)
        } else {
            failed = true
        }
    }
}
