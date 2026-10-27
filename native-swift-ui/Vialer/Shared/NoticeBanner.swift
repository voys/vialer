import SwiftUI
import UIKit

struct NoticeBanner: View {
    @Environment(AppContainer.self) private var container
    let notice: Notice
    @State private var showTelephonySettings = false
    @State private var showRedirect = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.primary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(notice.title).font(.subheadline.bold())
                    Text(notice.message).font(.footnote).foregroundStyle(Theme.infoText)
                }
                Spacer()
                Button { container.notices.dismiss() } label: {
                    Image(systemName: "xmark").font(.caption).foregroundStyle(Theme.grey4)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, -12)
                .padding(.trailing, -12)
                .accessibilityLabel(L10n.generic.button.close)
            }
            if let action = notice.actionTitle {
                Button(action) { perform() }
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.primary)
            }
        }
        .bannerCard(Theme.primary.opacity(0.12))
        .sheet(isPresented: $showTelephonySettings) {
            PortalWebView(page: .telephonySettings) {
                Task { await container.session.refreshUser(force: true); await container.notices.check() }
            }
        }
        .sheet(isPresented: $showRedirect) { TemporaryRedirectView() }
    }

    private func perform() {
        switch notice {
        case .microphoneDenied, .notificationsDenied:
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        case .noAppAccount:
            showTelephonySettings = true
        case .temporaryRedirect:
            showRedirect = true
        }
    }
}
