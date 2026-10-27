import SwiftUI

struct MainTabView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        @Bindable var container = container
        @Bindable var updates = container.updates
        TabView(selection: $container.selectedTab) {
            DialerView()
                .tabItem { Label(L10n.main.dialer.menu.title, systemImage: "circle.grid.3x3.fill") }
                .tag(MainTab.dialer)
            ColltactsView()
                .tabItem { Label(L10n.main.contacts.menu.title, systemImage: "person.crop.rectangle.stack") }
                .tag(MainTab.contacts)
            RecentsView()
                .tabItem { Label(L10n.main.recent.menu.title, systemImage: "clock.arrow.circlepath") }
                .tag(MainTab.recents)
            SettingsView()
                .tabItem { Label(L10n.main.settings.menu.title, systemImage: "person.crop.circle") }
                .tag(MainTab.settings)
                .badge(container.session.isRingingDeviceOffline ? "!" : nil)
        }
        .sheet(isPresented: $updates.showReleaseNotes) { ReleaseNotesSheet() }
        .task { await container.notices.check() }
        .onChange(of: container.session.user) { _, _ in Task { await container.notices.check() } }
    }
}
