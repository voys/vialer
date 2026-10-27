import SwiftUI

// MARK: - Avatar

struct AvatarView: View {
    var name: String
    var image: Data?
    var size: CGFloat = 40
    var statusColor: Color?

    private var initials: String {
        name.split(separator: " ").prefix(2).map { String($0.prefix(1)).uppercased() }.joined()
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image, let uiImage = UIImage(data: image) {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                } else {
                    Theme.avatarColor(for: name)
                        .overlay(
                            Text(initials.isEmpty ? "#" : initials)
                                .font(.system(size: size * 0.4, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())

            if let statusColor {
                Circle()
                    .fill(statusColor)
                    .frame(width: size * 0.3, height: size * 0.3)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
            }
        }
        // The name and status are read from the row text; the avatar is decorative.
        .accessibilityHidden(true)
    }
}

// MARK: - Dial pad

struct DialPadKey: Identifiable {
    let digit: Character
    let letters: String
    var id: Character { digit }

    static let all: [DialPadKey] = [
        .init(digit: "1", letters: ""), .init(digit: "2", letters: "ABC"), .init(digit: "3", letters: "DEF"),
        .init(digit: "4", letters: "GHI"), .init(digit: "5", letters: "JKL"), .init(digit: "6", letters: "MNO"),
        .init(digit: "7", letters: "PQRS"), .init(digit: "8", letters: "TUV"), .init(digit: "9", letters: "WXYZ"),
        .init(digit: "*", letters: ""), .init(digit: "0", letters: "+"), .init(digit: "#", letters: ""),
    ]
}

/// The Flutter keypad: 3 columns x 5 rows, cells capped at 104pt, keys at 80pt with a thin border,
/// and a bottom row with optional left/right slots around the primary button.
struct Keypad<Center: View, Left: View, Right: View>: View {
    var onDigit: (Character) -> Void
    var onLongPressZero: (() -> Void)? = nil
    @ViewBuilder var center: (CGFloat) -> Center
    @ViewBuilder var left: (CGFloat) -> Left
    @ViewBuilder var right: (CGFloat) -> Right

    static var keySize: CGFloat { 80 }
    private static var maxCell: CGFloat { 104 }

    init(onDigit: @escaping (Character) -> Void,
         onLongPressZero: (() -> Void)? = nil,
         @ViewBuilder center: @escaping (CGFloat) -> Center,
         @ViewBuilder left: @escaping (CGFloat) -> Left = { _ in EmptyView() },
         @ViewBuilder right: @escaping (CGFloat) -> Right = { _ in EmptyView() }) {
        self.onDigit = onDigit
        self.onLongPressZero = onLongPressZero
        self.center = center
        self.left = left
        self.right = right
    }

    var body: some View {
        GeometryReader { geo in
            let cellWidth = min(geo.size.width / 3, Self.maxCell)
            let cellHeight = min((geo.size.height - 32) / 5, Self.maxCell)
            let keySize = max(44, min(Self.keySize, cellWidth - 8, cellHeight - 8))
            let rows: [[DialPadKey]] = stride(from: 0, to: 12, by: 3).map { Array(DialPadKey.all[$0..<$0 + 3]) }
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(row) { key in
                            KeypadValueButton(key: key, size: keySize, onTap: { onDigit(key.digit) },
                                              onLongPress: key.digit == "0" ? onLongPressZero : nil)
                                .frame(width: cellWidth, height: cellHeight)
                        }
                    }
                }
                HStack(spacing: 0) {
                    left(keySize).frame(width: cellWidth, height: cellHeight)
                    center(keySize).frame(width: cellWidth, height: cellHeight)
                    right(keySize).frame(width: cellWidth, height: cellHeight)
                }
                .padding(.bottom, 32)
            }
            .frame(width: geo.size.width)
        }
    }
}

struct KeypadValueButton: View {
    let key: DialPadKey
    var size: CGFloat = 80
    var onTap: () -> Void
    var onLongPress: (() -> Void)?

    private var isNumber: Bool { key.digit.isNumber }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                Text(String(key.digit))
                    .font(.system(size: 32 * size / 80))
                    .foregroundStyle(isNumber ? Color.primary : Theme.grey5)
                Text(key.letters)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.grey5)
                    .frame(height: 14)
            }
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Theme.grey3, lineWidth: 1))
            .contentShape(Circle())
        }
        .buttonStyle(KeypadPressStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in onLongPress?() }
        )
        .accessibilityLabel(key.digit == "*" ? "star" : key.digit == "#" ? "pound" : String(key.digit))
        .accessibilityHint(key.letters)
    }
}

/// Subtle highlight on press, in place of Flutter's ink response.
struct KeypadPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(configuration.isPressed ? Theme.grey3 : Color.clear))
    }
}

/// The number strip above the keypad: centred 32pt number on a light grey band with the delete key
/// on the right (long press clears everything).
struct KeyInput: View {
    @Binding var text: String
    var canDelete = true
    var onDeleteAll: (() -> Void)? = nil

    private static let deleteSize: CGFloat = 32
    private static let deletePadding: CGFloat = 24

    var body: some View {
        HStack(spacing: 0) {
            Text(text)
                .font(.system(size: 32))
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity)
                .padding(.leading, canDelete ? Self.deleteSize + Self.deletePadding + 12 : 12)
                .padding(.trailing, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 56)
                .accessibilityLabel(text.isEmpty ? L10n.main.dialer.screenReader.phoneNumberInput
                                    : L10n.main.dialer.screenReader.phoneNumberInputPopulated(number: text))
            if canDelete {
                Button {
                    if !text.isEmpty { text.removeLast() }
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 24))
                        .foregroundStyle(text.isEmpty ? Theme.grey2 : Theme.grey5)
                        .frame(width: Self.deleteSize + 12, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(text.isEmpty)
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                    text = ""
                    onDeleteAll?()
                })
                .padding(.trailing, Self.deletePadding - 6)
                .accessibilityLabel(L10n.main.dialer.button.delete.hint)
            }
        }
        .background(Theme.grey3.opacity(0.5))
    }
}

/// Round call/hang-up/answer button, 64pt by default (80pt on the dialer), icon 24pt.
struct CallButton: View {
    enum Kind { case call, hangUp, transfer }
    var kind: Kind
    var size: CGFloat = 64
    var enabled = true
    var action: () -> Void

    private var icon: String {
        switch kind {
        case .call: return "phone.fill"
        case .hangUp: return "phone.down.fill"
        case .transfer: return "arrow.left.arrow.right"
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(enabled ? (kind == .hangUp ? Theme.red : Theme.green) : Theme.grey3)
                .clipShape(Circle())
                .shadow(color: .black.opacity(enabled ? 0.2 : 0), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(kind == .hangUp ? L10n.main.call.ongoing.hangUp : kind == .transfer ? L10n.main.call.ongoing.actions.transfer.label : L10n.generic.button.call)
    }
}

// MARK: - Search

struct SearchField: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.grey4)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.grey4) }
            }
        }
        .padding(8)
        .background(Theme.grey7)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Placeholders

struct PlaceholderView: View {
    var systemImage: String
    var title: String
    var message: String? = nil
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.system(size: 48)).foregroundStyle(Theme.grey4)
            Text(title).font(.headline).multilineTextAlignment(.center)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(Theme.infoText).multilineTextAlignment(.center)
            }
            if let buttonTitle, let action {
                Button(action: action) { Text(buttonTitle) }.buttonStyle(PrimaryButtonStyle()).frame(maxWidth: 240)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Colleague status

extension Colleague {
    var statusColor: Color {
        if isUnconnectedVoipAccount { return Theme.unknownAccent }
        if let context = mostRelevantContext {
            return context == .inCall || context == .ringing ? Theme.busyAccent : Theme.availableAccent
        }
        switch status {
        case .available, .availableForColleagues: return Theme.availableAvatar
        case .busy: return Theme.busyAvatar
        case .doNotDisturb: return Theme.unavailableAccent
        case .offline: return Theme.offlineBackground
        case .unknown, .none: return isAvailableOnMobileAppOrFixedDestination ? Theme.availableAvatar : Theme.grey2
        }
    }

    var statusText: String {
        if isUnconnectedVoipAccount { return number ?? "" }
        if let context = mostRelevantContext {
            return context == .inCall ? L10n.main.colleagues.context.inCall : L10n.main.colleagues.context.ringing
        }
        switch status {
        case .available: return L10n.main.colleagues.status.available
        case .availableForColleagues: return L10n.main.colleagues.status.availableInternally
        case .busy: return L10n.main.colleagues.status.busy
        case .doNotDisturb: return L10n.main.colleagues.status.doNotDisturb
        case .offline: return L10n.main.colleagues.status.offline
        case .unknown, .none:
            return isAvailableOnMobileAppOrFixedDestination ? L10n.main.colleagues.status.available : L10n.main.colleagues.status.unknown
        }
    }
}

extension UserAvailabilityStatus {
    var color: Color {
        switch self {
        case .available: return Theme.availableAccent
        case .availableForColleagues: return Theme.availableAccent
        case .doNotDisturb: return Theme.unavailableAccent
        case .offline: return Theme.offlineBackground
        }
    }

    var backgroundColor: Color {
        switch self {
        case .available, .availableForColleagues: return Theme.availableBackground
        case .doNotDisturb: return Theme.unavailableBackground
        case .offline: return Theme.offlineBackground
        }
    }

    var foregroundColor: Color {
        self == .offline ? Theme.offlineAccent : color
    }
}

// MARK: - T9

enum T9 {
    private static let map: [Character: Character] = {
        var m: [Character: Character] = [:]
        for (digit, letters) in [("2", "abc"), ("3", "def"), ("4", "ghi"), ("5", "jkl"), ("6", "mno"), ("7", "pqrs"), ("8", "tuv"), ("9", "wxyz")] {
            letters.forEach { m[$0] = Character(digit) }
        }
        return m
    }()

    static func digits(for name: String) -> String {
        String(name.folding(options: .diacriticInsensitive, locale: nil).lowercased().compactMap { c in
            if c.isNumber { return c }
            if c == " " { return " " }
            return map[c]
        })
    }

    /// True when the typed digits match the start of the full name or of any word in it.
    static func matches(name: String, input: String) -> Bool {
        guard !input.isEmpty else { return false }
        let encoded = digits(for: name)
        if encoded.replacingOccurrences(of: " ", with: "").hasPrefix(input) { return true }
        return encoded.split(separator: " ").contains { $0.hasPrefix(input) }
    }
}

// MARK: - Formatting

extension Date {
    var recentsDayLabel: String {
        if Calendar.current.isDateInToday(self) { return L10n.main.recent.list.headers.today }
        if Calendar.current.isDateInYesterday(self) { return L10n.main.recent.list.headers.yesterday }
        return formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

extension TimeInterval {
    var shortDuration: String {
        let total = Int(self)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
