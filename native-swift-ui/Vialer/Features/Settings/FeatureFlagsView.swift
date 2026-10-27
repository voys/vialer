import SwiftUI

/// Read-only list of the `FEATURE_*` flags baked in from `.env` at build time.
struct FeatureFlagsView: View {
    private static let flags: [(name: String, isEnabled: Bool)] = [
        ("Messaging apps survey", Env.isMessagingAppsSurveyEnabled),
    ]

    private var strings: L10n.main.settings.list.advancedSettings.troubleshooting.featureFlags.Type {
        L10n.main.settings.list.advancedSettings.troubleshooting.featureFlags.self
    }

    var body: some View {
        List {
            if Self.flags.isEmpty {
                Text(strings.none).foregroundStyle(Theme.infoText)
            } else {
                ForEach(Self.flags, id: \.name) { flag in
                    LabeledContent(flag.name) {
                        Image(systemName: flag.isEnabled ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(flag.isEnabled ? Theme.green : Theme.grey4)
                            .accessibilityLabel(flag.isEnabled ? N("generic.on") : N("generic.off"))
                    }
                }
            }
        }
        .navigationTitle(strings.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
