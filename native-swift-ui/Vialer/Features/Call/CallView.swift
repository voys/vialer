import SwiftUI

/// The ongoing call screen: gradient header, action grid, hang-up. The DTMF keypad and the
/// transfer screen replace the body in place, as the Flutter nested navigator does.
struct CallView: View {
    @Environment(AppContainer.self) private var container
    @State private var showKeypad = false
    @State private var showTransfer = false

    private var calls: CallManager { container.calls }
    private var active: CallSnapshot.CallInfo? { calls.snapshot?.activeCall ?? calls.lastEndedCall }
    private var isFinished: Bool { calls.phase == .ended }

    var body: some View {
        Group {
            if showTransfer, let active {
                TransferView(activeCall: active) { number in
                    if let number { calls.beginTransfer(to: number) }
                    showTransfer = false
                }
            } else {
                callBody
            }
        }
        .background(Color(.systemBackground))
        .interactiveDismissDisabled()
        .onChange(of: calls.phase) { _, phase in
            if phase == .ended { showKeypad = false; showTransfer = false }
        }
    }

    private var callBody: some View {
        VStack(spacing: 0) {
            CallHeaderContainer {
                VStack(spacing: 0) {
                    if let inactive = calls.snapshot?.inactiveCall {
                        CallTransferBar {
                            Text(inactive.heading).bold()
                            + Text(" - \(inactive.prettyDuration) - ")
                            + Text(inactive.isOnHold ? L10n.main.call.ongoing.state.callOnHold : L10n.main.call.ongoing.state.callEnded)
                        }
                    }
                    CallHeader(call: active, statusText: statusText)
                }
            }

            if showKeypad {
                CallKeypad(onCancel: { showKeypad = false }, isFinished: isFinished) { calls.end() }
            } else if calls.phase == .ringing {
                Spacer()
                incomingActions
                Spacer()
            } else {
                Spacer()
                actions
            }
            if calls.showPoorConnectionWarning && !isFinished {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.main.call.ongoing.connectionWarning.title).font(.subheadline.bold())
                        Text(L10n.main.call.ongoing.connectionWarning.description).font(.footnote)
                    }
                    Spacer()
                }
                .foregroundStyle(.white)
                .bannerCard(Theme.red)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.default, value: calls.showPoorConnectionWarning)
    }

    private var statusText: String {
        guard let active else { return "" }
        switch calls.phase {
        case .ringing: return L10n.main.call.incoming.subtitle
        case .starting: return active.state == .connected ? active.prettyDuration : L10n.main.call.ongoing.state.calling
        case .ended: return L10n.main.call.ongoing.state.callEnded
        default:
            if active.isOnHold || active.state == .heldByLocal { return L10n.main.call.ongoing.state.callOnHold }
            if active.state == .heldByRemote { return N("call.state.heldByRemote") }
            return active.prettyDuration
        }
    }

    private var incomingActions: some View {
        HStack(spacing: 80) {
            VStack(spacing: 8) {
                CallButton(kind: .hangUp) { calls.decline() }
                Text(L10n.main.call.incoming.decline).font(.system(size: 16))
            }
            VStack(spacing: 8) {
                CallButton(kind: .call) { Task { await calls.answer() } }
                Text(L10n.main.call.incoming.answer).font(.system(size: 16))
            }
        }
    }

    private var actions: some View {
        let snapshot = calls.snapshot
        let isOnHold = active?.isOnHold ?? false
        let isTransferring = snapshot?.inactiveCall != nil
        let isActionable = !isFinished && calls.phase != .starting
        let strings = L10n.main.call.ongoing.actions.self
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                CallActionButton(title: strings.mute, systemImage: "mic.slash.fill",
                                 isActive: snapshot?.isMuted == true, isEnabled: !isOnHold && !isFinished) { calls.toggleMute() }
                    .frame(maxWidth: .infinity)
                CallActionButton(title: strings.keypad.label, systemImage: "circle.grid.3x3.fill",
                                 isActive: false, isEnabled: !isFinished) { showKeypad = true }
                    .frame(maxWidth: .infinity)
                audioRouteButton
                    .frame(maxWidth: .infinity)
            }
            Spacer().frame(height: 48)
            HStack(spacing: 0) {
                Spacer().frame(maxWidth: .infinity)
                CallActionButton(title: isTransferring ? strings.merge : strings.transfer.label,
                                 systemImage: isTransferring ? "arrow.triangle.merge" : "arrow.left.arrow.right",
                                 isActive: false, isEnabled: isActionable) {
                    if isTransferring {
                        calls.mergeTransfer()
                    } else {
                        Task {
                            try? await Task.sleep(for: .seconds(0.5))
                            calls.hold()
                        }
                        showTransfer = true
                    }
                }
                .frame(maxWidth: .infinity).layoutPriority(2)
                CallActionButton(title: strings.hold, systemImage: "pause.fill", isActive: isOnHold, isEnabled: isActionable) { calls.toggleHold() }
                    .frame(maxWidth: .infinity).layoutPriority(2)
                Spacer().frame(maxWidth: .infinity)
            }
            Spacer().frame(height: 48)
            CallButton(kind: .hangUp, enabled: !isFinished) { calls.end() }
            Spacer().frame(height: 32)
        }
        .padding(.horizontal, 12)
    }

    /// Without Bluetooth the button toggles phone/speaker; with Bluetooth it opens the system picker.
    private var audioRouteButton: some View {
        let snapshot = calls.snapshot
        let route = snapshot?.currentRoute ?? .phone
        let hasBluetooth = snapshot?.availableRoutes.contains(.bluetooth) ?? false
        let strings = L10n.main.call.ongoing.actions.audioRoute.self
        let label: String
        let icon: String
        if !hasBluetooth || route == .speaker {
            label = strings.speaker
            icon = "speaker.wave.2.fill"
        } else if route == .bluetooth {
            label = (snapshot?.bluetoothDeviceName).flatMap { $0.isEmpty ? nil : $0 } ?? strings.bluetooth
            icon = "headphones"
        } else {
            label = strings.phone
            icon = "phone.fill"
        }
        return CallActionButton(title: label, systemImage: icon,
                                isActive: !hasBluetooth && route == .speaker, isEnabled: !isFinished) {
            if hasBluetooth {
                calls.launchAudioRoutePicker()
            } else {
                calls.routeAudio(route == .phone ? .speaker : .phone)
            }
        }
    }
}

// MARK: - Header

struct CallHeaderContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .padding(.top, 54)
            .background(Theme.primaryGradient)
            .ignoresSafeArea(edges: .top)
    }
}

struct CallHeader: View {
    let call: CallSnapshot.CallInfo?
    let statusText: String

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 12)
            Text(call?.heading ?? "")
                .font(.system(size: 32, weight: .light))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Spacer().frame(height: 2)
            Text(call?.subheading ?? " ")
                .font(.system(size: 16))
            Spacer().frame(height: 4)
            Text(statusText)
                .font(.system(size: 16, weight: .medium).monospacedDigit())
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(Theme.gradientStart)
                .clipShape(RoundedRectangle(cornerRadius: 13.5))
            Spacer().frame(height: 12)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
    }
}

struct CallTransferBar: View {
    @ViewBuilder var text: () -> Text

    var body: some View {
        text()
            .font(.system(size: 16))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Action button

/// 64pt circle; brand fill with white icon when active, otherwise a bare grey icon. Label beneath.
struct CallActionButton: View {
    var title: String
    var systemImage: String
    var isActive: Bool
    var isEnabled = true
    var action: () -> Void

    private var iconColor: Color {
        if isActive { return .white }
        return isEnabled ? .primary : Theme.disabledText
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 28))
                    .foregroundStyle(iconColor)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(isActive ? Theme.primary : Color.clear))
                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(isEnabled ? .primary : Theme.disabledText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .accessibilityValue(isActive ? L10n.generic.on : L10n.generic.off)
    }
}

// MARK: - In-call keypad

/// DTMF keypad shown in place of the actions: number strip without delete, X to close bottom-left,
/// hang-up in the centre.
struct CallKeypad: View {
    @Environment(AppContainer.self) private var container
    var onCancel: () -> Void
    var isFinished: Bool
    var onHangUp: () -> Void
    @State private var sent = ""

    var body: some View {
        VStack(spacing: 0) {
            KeyInput(text: $sent, canDelete: false)
            Spacer().frame(height: 24)
            Keypad(
                onDigit: { digit in
                    sent.append(digit)
                    container.calls.sendDtmf(String(digit))
                },
                center: { keySize in CallButton(kind: .hangUp, size: min(64, keySize), enabled: !isFinished, action: onHangUp) },
                left: { keySize in
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 28))
                            .foregroundStyle(Theme.grey5)
                            .frame(width: keySize, height: keySize)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.generic.button.close)
                }
            )
            .padding(.horizontal, 8)
        }
    }
}

// MARK: - Transfer

/// The transfer screen: "Transferring <name> to" bar over the gradient, then a dial pad whose
/// primary button starts the attended transfer. Bottom-left closes, bottom-right picks a contact.
struct TransferView: View {
    @Environment(AppContainer.self) private var container
    let activeCall: CallSnapshot.CallInfo
    var onDone: (String?) -> Void
    @State private var number = ""
    @State private var showContacts = false

    var body: some View {
        VStack(spacing: 0) {
            CallHeaderContainer {
                CallTransferBar {
                    Text(L10n.main.call.ongoing.state.transferToStart + " ")
                    + Text(activeCall.heading).bold()
                    + Text(" " + L10n.main.call.ongoing.state.transferToEnd)
                }
            }
            Spacer().frame(height: 58)
            KeyInput(text: $number, onDeleteAll: { number = "" })
            Spacer().frame(height: 24)
            Keypad(
                onDigit: { number.append($0); container.calls.playTone($0) },
                onLongPressZero: {
                    if number.last == "0" { number.removeLast() }
                    number.append("+")
                },
                center: { keySize in
                    CallButton(kind: .transfer, size: keySize, enabled: !number.isEmpty) {
                        Metrics.track("call-transfer-initiated", ["via": "dialer"])
                        onDone(number)
                    }
                },
                left: { keySize in
                    Button { onDone(nil) } label: {
                        Image(systemName: "xmark").font(.system(size: 28)).foregroundStyle(Theme.grey5)
                            .frame(width: keySize, height: keySize).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.generic.button.close)
                },
                right: { keySize in
                    Button { showContacts = true } label: {
                        Image(systemName: "person.crop.rectangle.stack").font(.system(size: 28)).foregroundStyle(Theme.grey5)
                            .frame(width: keySize, height: keySize).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.main.contacts.title)
                }
            )
            .padding(.horizontal, 8)
        }
        .sheet(isPresented: $showContacts) {
            ColltactPickerView { picked in
                showContacts = false
                Metrics.track("call-transfer-initiated", ["via": "contact"])
                onDone(picked)
            }
        }
        .onAppear { Metrics.track("call-transfer-ui-presented") }
    }
}
