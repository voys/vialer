import SwiftUI

/// Connectivity, notice and update banners stacked as inline cards. Shown as the first rows of each
/// tab's scroll view so the navigation bar behaves normally.
struct BannersView: View {
    @Environment(AppContainer.self) private var container
    /// Inset-grouped lists already indent their sections, so they pass 0.
    var horizontalPadding: CGFloat = 16

    static func hasContent(_ container: AppContainer) -> Bool {
        !container.connectivity.isConnected || container.notices.notice != nil
            || (container.updates.showStoreReminder && container.updates.storeUpdate != nil)
    }

    var body: some View {
        if Self.hasContent(container) {
            VStack(spacing: 8) {
                if !container.connectivity.isConnected {
                    ConnectivityBanner()
                }
                if let notice = container.notices.notice {
                    NoticeBanner(notice: notice)
                }
                if container.updates.showStoreReminder, let update = container.updates.storeUpdate {
                    UpdateReminderBanner(update: update)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 8)
        }
    }
}

/// `BannersView` as a list section with no row chrome.
struct BannerSection: View {
    @Environment(AppContainer.self) private var container
    var horizontalPadding: CGFloat = 16

    var body: some View {
        if BannersView.hasContent(container) {
            Section {
                BannersView(horizontalPadding: horizontalPadding)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
}

/// A segmented control as a plain list row under the navigation title.
struct PickerRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Section {
            content()
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

/// A full-width placeholder as a list row, for empty and error states inside a list.
struct PlaceholderRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Section {
            content()
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

extension View {
    /// Card styling shared by the inline banners.
    func bannerCard(_ background: Color) -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
