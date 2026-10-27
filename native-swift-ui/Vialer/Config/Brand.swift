import Foundation
import UIKit
import SwiftUI

/// One brand's configuration, ported from `brands/<identifier>.json` and `Colors.<brand>` in the
/// Flutter theme. The active brand is picked by the `BrandIdentifier` Info.plist value, which each
/// build configuration sets (see `project.yml`).
struct BrandConfig {
    let identifier: String
    let appName: String
    let bundleId: String
    let portalURL: URL
    let voipgridAPIBaseURL: URL
    let sipDomain: String
    let middlewareURL: URL
    let privacyPolicyURL: URL
    let supportURL: URL?
    let supportURLNL: URL?
    let aboutURL: URL?
    let signUpURL: URL?
    let holodeckEnvironment: String
    let palette: BrandPalette

    var callwakerURL: URL { holodeck("callwaker") }
    var availabilityServiceURL: URL { holodeck("user-status") }
    var sharedContactsURL: URL { holodeck("contactbook") }
    var openingHoursBasicURL: URL { holodeck("opening-hours-basic/client/") }
    var phoneNumberValidationURL: URL { holodeck("number-normalisation/v1/") }
    var businessAvailabilityURL: URL { holodeck("business-availability/clients/") }
    var featureAnnouncementsURL: URL { holodeck("feature-announcements/") }
    var resgateURL: URL { URL(string: "wss://resgate.eu-\(holodeckEnvironment).holodeck.voys.nl")! }
    var passwordResetURL: URL { portalURL.appendingPathComponent("user/password_reset/") }

    private func holodeck(_ path: String) -> URL {
        URL(string: "https://api.eu-\(holodeckEnvironment).holodeck.voys.nl/\(path)")!
    }

    static let voys = BrandConfig(
        identifier: "voys", appName: "Voys", bundleId: "com.voys.app",
        portalURL: URL(string: "https://freedom.voys.nl")!,
        voipgridAPIBaseURL: URL(string: "https://partner.voys.co/api/")!,
        sipDomain: "sip.encryptedsip.com",
        middlewareURL: URL(string: "https://vmex.eu-production.holodeck.voys.nl")!,
        privacyPolicyURL: URL(string: "https://www.voys.nl/app-privacy/")!,
        supportURL: URL(string: "https://www.voys.co/contact/"),
        supportURLNL: URL(string: "https://booking.voys.nl"),
        aboutURL: URL(string: "https://www.voys.nl/hulp/toestellen/voys-4g-app/"),
        signUpURL: nil,
        holodeckEnvironment: "production",
        palette: .voys
    )

    static let vialer = BrandConfig(
        identifier: "vialer", appName: "Vialer", bundleId: "com.voipgrid.vialer",
        portalURL: URL(string: "https://partner.voys.co")!,
        voipgridAPIBaseURL: URL(string: "https://partner.voys.co/api/")!,
        sipDomain: "sip.encryptedsip.com",
        middlewareURL: URL(string: "https://vmex.eu-production.holodeck.voys.nl")!,
        privacyPolicyURL: URL(string: "https://vialerapp.com/privacy/")!,
        supportURL: nil, supportURLNL: nil, aboutURL: nil, signUpURL: nil,
        holodeckEnvironment: "production",
        palette: .vialer
    )

    static let vialerStaging = BrandConfig(
        identifier: "vialerStaging", appName: "Vialer Staging", bundleId: "com.voipgrid.vialer",
        portalURL: URL(string: "https://staging.voipgrid.nl")!,
        voipgridAPIBaseURL: URL(string: "https://staging.voipgrid.nl/api/")!,
        sipDomain: "staging.encryptedsip.com",
        middlewareURL: URL(string: "https://vmex.eu-staging.holodeck.voys.nl")!,
        privacyPolicyURL: URL(string: "https://vialerapp.com/privacy/")!,
        supportURL: nil, supportURLNL: nil, aboutURL: nil, signUpURL: nil,
        holodeckEnvironment: "staging",
        palette: .vialer
    )

    static let verbonden = BrandConfig(
        identifier: "verbonden", appName: "Verbonden", bundleId: "nl.verbonden.app",
        portalURL: URL(string: "https://partner.voys.co")!,
        voipgridAPIBaseURL: URL(string: "https://partner.voys.co/api/")!,
        sipDomain: "sip.encryptedsip.com",
        middlewareURL: URL(string: "https://vmex.eu-production.holodeck.voys.nl")!,
        privacyPolicyURL: URL(string: "https://verbonden.nl/app/privacy")!,
        supportURL: URL(string: "https://verbonden.nl/contact"), supportURLNL: nil, aboutURL: nil, signUpURL: nil,
        holodeckEnvironment: "production",
        palette: .verbonden
    )

    static let annabel = BrandConfig(
        identifier: "annabel", appName: "ANNAbel", bundleId: "com.bellenmetannabel.app",
        portalURL: URL(string: "https://partner.voys.co")!,
        voipgridAPIBaseURL: URL(string: "https://partner.voys.co/api/")!,
        sipDomain: "sip.encryptedsip.com",
        middlewareURL: URL(string: "https://vmex.eu-production.holodeck.voys.nl")!,
        privacyPolicyURL: URL(string: "https://bellenmetannabel.nl/privacy-app/")!,
        supportURL: URL(string: "https://bellenmetannabel.nl/contact"), supportURLNL: nil, aboutURL: nil, signUpURL: nil,
        holodeckEnvironment: "production",
        palette: .annabel
    )

    static let all: [BrandConfig] = [voys, vialer, vialerStaging, verbonden, annabel]
}

/// Brand colours from `Colors.<brand>` in `lib/presentation/resources/theme/colors.dart`. The
/// `*OnDark` values have no Flutter counterpart: they keep the primary readable and the tinted
/// backgrounds subtle on dark system backgrounds.
struct BrandPalette {
    let primary: UInt32
    let primaryDark: UInt32
    let primaryDarker: UInt32
    let primaryLighter: UInt32
    let primaryLight: UInt32
    let gradientStart: UInt32
    let gradientEnd: UInt32
    let buttonShade: UInt32
    let primaryOnDark: UInt32
    let primaryLightOnDark: UInt32

    static let vialer = BrandPalette(primary: 0xFFFF7B24, primaryDark: 0xFFD45400, primaryDarker: 0xFFE6640E,
                                     primaryLighter: 0xFFFDBA74, primaryLight: 0xFFFFEDD5,
                                     gradientStart: 0xFFFF8213, gradientEnd: 0xFFE94E1B, buttonShade: 0xFFFF7B24,
                                     primaryOnDark: 0xFFFF9447, primaryLightOnDark: 0xFF3D2410)
    static let voys = BrandPalette(primary: 0xFF270597, primaryDark: 0xFF1E1B4B, primaryDarker: 0xFF000577,
                                   primaryLighter: 0xFFB7B2F8, primaryLight: 0xFFF0F0FF,
                                   gradientStart: 0xFF270597, gradientEnd: 0xFF7F67D1, buttonShade: 0xFF1E1B4B,
                                   primaryOnDark: 0xFF8F7BE0, primaryLightOnDark: 0xFF1E1B4B)
    static let verbonden = BrandPalette(primary: 0xFF3336AD, primaryDark: 0xFF01243C, primaryDarker: 0xFF1A2D75,
                                        primaryLighter: 0xFF8385D6, primaryLight: 0xFFD2D3FF,
                                        gradientStart: 0xFF3336AD, gradientEnd: 0xFF01243C, buttonShade: 0xFF01243C,
                                        primaryOnDark: 0xFF8385D6, primaryLightOnDark: 0xFF1A2D75)
    static let annabel = BrandPalette(primary: 0xFF645394, primaryDark: 0xFF160E2D, primaryDarker: 0xFF382E52,
                                      primaryLighter: 0xFFABA1C5, primaryLight: 0xFFEDE9F9,
                                      gradientStart: 0xFF645394, gradientEnd: 0xFF160E2D, buttonShade: 0xFF160E2D,
                                      primaryOnDark: 0xFFABA1C5, primaryLightOnDark: 0xFF2A2140)
}

/// The active brand. Static accessors keep call sites short.
enum Brand {
    static let current: BrandConfig = {
        let identifier = Bundle.main.infoDictionary?["BrandIdentifier"] as? String ?? ""
        if let match = BrandConfig.all.first(where: { $0.identifier == identifier }) { return match }
        AppLog.warning("Unknown BrandIdentifier '\(identifier)', falling back to Voys")
        return .voys
    }()

    static var identifier: String { current.identifier }
    static var appName: String { current.appName }
    static var bundleId: String { Bundle.main.bundleIdentifier ?? current.bundleId }
    static var portalURL: URL { current.portalURL }
    static var voipgridAPIBaseURL: URL { current.voipgridAPIBaseURL }
    static var sipDomain: String { current.sipDomain }
    static var middlewareURL: URL { current.middlewareURL }
    static var callwakerURL: URL { current.callwakerURL }
    static var availabilityServiceURL: URL { current.availabilityServiceURL }
    static var sharedContactsURL: URL { current.sharedContactsURL }
    static var openingHoursBasicURL: URL { current.openingHoursBasicURL }
    static var phoneNumberValidationURL: URL { current.phoneNumberValidationURL }
    static var businessAvailabilityURL: URL { current.businessAvailabilityURL }
    static var featureAnnouncementsURL: URL { current.featureAnnouncementsURL }
    static var resgateURL: URL { current.resgateURL }
    static var privacyPolicyURL: URL { current.privacyPolicyURL }
    static var aboutURL: URL? { current.aboutURL }
    static var passwordResetURL: URL { current.passwordResetURL }
    static var signUpURL: URL? { current.signUpURL }

    /// Dutch users get the NL support page when the brand has one, as in the Flutter app.
    static var supportURL: URL? {
        if Locale.current.language.languageCode?.identifier == "nl", let nl = current.supportURLNL { return nl }
        return current.supportURL
    }
}

enum BuildInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    static var userAgent: String { "\(Brand.appName) iOS v\(version)" }

    static var osVersion: String { UIDevice.current.systemVersion }

    static var isSandboxPush: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
