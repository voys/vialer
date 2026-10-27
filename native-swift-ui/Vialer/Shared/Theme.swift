import SwiftUI

extension Color {
    init(hex: UInt32) {
        let a = Double((hex >> 24) & 0xFF) / 255
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// A colour that switches with the interface style.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

/// Brand colours come from the active brand's palette, with lighter primaries on dark
/// backgrounds; the shared tokens below are the same for every brand in the Flutter theme.
enum Theme {
    private static var palette: BrandPalette { Brand.current.palette }

    static var primary: Color { Color(light: palette.primary, dark: palette.primaryOnDark) }
    static var primaryDark: Color { Color(hex: palette.primaryDark) }
    static var primaryDarker: Color { Color(light: palette.primaryDarker, dark: palette.primaryOnDark) }
    static var primaryLighter: Color { Color(hex: palette.primaryLighter) }
    static var primaryLight: Color { Color(light: palette.primaryLight, dark: palette.primaryLightOnDark) }
    static var gradientStart: Color { Color(hex: palette.gradientStart) }
    static var gradientEnd: Color { Color(hex: palette.gradientEnd) }
    static let onPrimary = Color.white
    static var buttonShade: Color { Color(hex: palette.buttonShade) }

    // Neutral tokens map to system semantic colours so they adapt to dark mode; the Flutter values
    // (666666, CCCCCC, D8D8D8, E0E0E0, 8F8F8F, F6F6F6) were their light-mode equivalents.
    static let infoText = Color(.secondaryLabel)
    static let disabledText = Color(.tertiaryLabel)
    static let grey1 = Color(.systemGray3)
    static let grey2 = Color(.systemGray4)
    static let grey3 = Color(.systemGray5)
    static let grey4 = Color(.systemGray)
    static let grey5 = Color(.systemGray2)
    static let grey6 = Color(.secondaryLabel)
    static let grey7 = Color(.secondarySystemBackground)
    static let settingsHighlight = Color(.tertiarySystemBackground)

    static let green = Color(hex: 0xFF28CA42)
    static let red = Color(hex: 0xFFDA534F)
    static let answeredElsewhere = Color(hex: 0xFF1F86FF)

    static let availableBackground = Color(hex: 0xFFACF5A6)
    static let availableAccent = Color(hex: 0xFF046614)
    static let availableAvatar = Color(hex: 0xFF63E06F)
    static let busyBackground = Color(hex: 0xFFFFADAD)
    static let busyAccent = Color(hex: 0xFF8F0A06)
    static let busyAvatar = Color(hex: 0xFFFFA257)
    static let unavailableBackground = Color(hex: 0xFFFFD0A3)
    static let unavailableAccent = Color(hex: 0xFFD45400)
    static let unknownBackground = Color(light: 0xFFF5F5F5, dark: 0xFF3A3A3C)
    static let unknownAccent = Color(light: 0xFF666666, dark: 0xFFAEAEB2)
    static let offlineBackground = Color(hex: 0xFF2A3041)
    static let offlineAccent = Color.white

    static var primaryGradient: LinearGradient {
        LinearGradient(colors: [gradientStart, gradientEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let fieldCornerRadius: CGFloat = 8

    /// Deterministic avatar color based on a name, mirroring the Flutter helper.
    static func avatarColor(for name: String) -> Color {
        let palette: [Color] = [
            Color(hex: 0xFFEF5350), Color(hex: 0xFFEC407A), Color(hex: 0xFFAB47BC),
            Color(hex: 0xFF7E57C2), Color(hex: 0xFF5C6BC0), Color(hex: 0xFF42A5F5),
            Color(hex: 0xFF29B6F6), Color(hex: 0xFF26C6DA), Color(hex: 0xFF26A69A),
            Color(hex: 0xFF66BB6A), Color(hex: 0xFF9CCC65), Color(hex: 0xFFFFA726),
            Color(hex: 0xFFFF7043), Color(hex: 0xFF8D6E63), Color(hex: 0xFF78909C),
        ]
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(filled ? Theme.primary : Color.clear)
            .foregroundStyle(filled ? Theme.onPrimary : Theme.primary)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.fieldCornerRadius)
                    .stroke(Theme.primary, lineWidth: filled ? 0 : 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.fieldCornerRadius))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct StylizedTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .background(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.fieldCornerRadius)
                    .stroke(Theme.grey1, lineWidth: 1)
            )
    }
}
