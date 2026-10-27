import SwiftUI
import UIKit

/// The Flutter `T9DialPad`: a two-row T9 suggestion list, divider, number strip, keypad.
struct DialerView: View {
    @Environment(AppContainer.self) private var container
    @State private var number = ""
    @State private var clipboardHasNumber = false
    @State private var chipDismissed = false

    private static let suggestionRowHeight: CGFloat = 66

    private var suggestions: [Colltact] {
        let input = number.filter(\.isNumber)
        guard input.count >= 2 else { return [] }
        let contacts = container.colltacts.contacts.filter { T9.matches(name: $0.displayName, input: input) }.map(Colltact.contact)
        let colleagues = container.colltacts.colleaguesWithPresence.filter { T9.matches(name: $0.name, input: input) && $0.number != nil }.map(Colltact.colleague)
        let shared = container.colltacts.sharedContacts.filter { T9.matches(name: $0.simpleDisplayName, input: input) }.map(Colltact.shared)
        return Array((contacts + colleagues + shared).prefix(30))
    }

    private var showChip: Bool { clipboardHasNumber && number.isEmpty && !chipDismissed }

    var body: some View {
        VStack(spacing: 0) {
            BannersView().padding(.top, 8)

            ZStack(alignment: .bottom) {
                List(suggestions) { colltact in
                    Button {
                        Metrics.track("t9-colltact-selected")
                        number = colltact.primaryNumber ?? ""
                    } label: {
                        ColltactRow(colltact: colltact)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                if showChip {
                    Button {
                        pasteFromClipboard()
                        chipDismissed = true
                    } label: {
                        Label(L10n.main.dialer.clipboard.copyPhoneNumber.title, systemImage: "doc.on.clipboard")
                            .font(.subheadline)
                            .foregroundStyle(Theme.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.primary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 10)
                }
            }
            .frame(height: Self.suggestionRowHeight * 2)

            Divider()

            KeyInput(text: $number, onDeleteAll: { number = "" })

            Spacer().frame(height: 24)

            Keypad(
                onDigit: { digit in
                    number.append(digit)
                    container.calls.playTone(digit)
                },
                onLongPressZero: {
                    if number.last == "0" { number.removeLast() }
                    number.append("+")
                },
                center: { keySize in
                    CallButton(kind: .call, size: keySize) {
                        if number.isEmpty {
                            number = LocalStore.shared.string(.lastDialedNumber) ?? ""
                        } else {
                            let target = number
                            number = ""
                            container.call(target)
                        }
                    }
                }
            )
            .padding(.horizontal, 8)
        }
        .onAppear {
            if let pending = container.pendingDialerNumber {
                number = pending
                container.pendingDialerNumber = nil
            }
            chipDismissed = false
            checkClipboard()
        }
        .onChange(of: container.pendingDialerNumber) { _, value in
            if let value {
                number = value
                container.pendingDialerNumber = nil
            }
        }
        .onChange(of: number) { _, value in
            if !value.isEmpty { chipDismissed = true }
        }
    }

    private func checkClipboard() {
        guard UIPasteboard.general.hasStrings else {
            clipboardHasNumber = false
            return
        }
        UIPasteboard.general.detectPatterns(for: [\.phoneNumbers]) { result in
            DispatchQueue.main.async {
                if case .success(let patterns) = result {
                    clipboardHasNumber = patterns.contains(\.phoneNumbers)
                } else {
                    clipboardHasNumber = false
                }
            }
        }
    }

    private func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string else { return }
        let cleaned = text.replacingOccurrences(of: "[^0-9+*#]", with: "", options: .regularExpression)
        if !cleaned.isEmpty { number = cleaned }
    }
}
