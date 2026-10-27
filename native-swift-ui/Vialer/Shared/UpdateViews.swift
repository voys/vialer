import SwiftUI

struct ReleaseNotesSheet: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let notes = container.updates.releaseNotesForPlatform
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "star.fill").font(.system(size: 40)).foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity)
                    Text(L10n.main.update.releaseNotes.header.subtitle(version: BuildInfo.version))
                        .font(.subheadline).foregroundStyle(Theme.infoText)
                        .frame(maxWidth: .infinity)
                    if notes.isEmpty {
                        Text("• " + L10n.main.update.releaseNotes.noneForPlatform)
                    } else {
                        ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                            Text(note)
                        }
                    }
                }
                .padding(24)
            }
            .navigationTitle(L10n.main.update.releaseNotes.header.title(appName: Brand.appName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.generic.button.close) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Fifteen-second reminder that a newer version is in the App Store.
struct UpdateReminderBanner: View {
    @Environment(AppContainer.self) private var container
    let update: StoreUpdate

    var body: some View {
        HStack {
            Image(systemName: "arrow.down.circle.fill")
            Text(L10n.main.updateReminder.title).font(.subheadline)
            Spacer()
            Link(L10n.main.updateReminder.button, destination: update.storeURL)
                .font(.subheadline.bold())
            Button { container.updates.showStoreReminder = false } label: {
                Image(systemName: "xmark").font(.caption)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -12)
            .padding(.trailing, -12)
            .accessibilityLabel(L10n.generic.button.close)
        }
        .foregroundStyle(Theme.primary)
        .bannerCard(Theme.primary.opacity(0.12))
    }
}
