import SwiftUI
import WebKit

/// Pages in the VoIPGRID portal that the app opens with an auto-login token.
enum PortalPage {
    case dialPlan, stats, calls, openingHoursBasicList, openingHoursBasicEdit, addVoicemail
    case telephonySettings, featureAnnouncements, intelligence, addDestination

    var title: String {
        switch self {
        case .dialPlan: return L10n.main.settings.list.portalLinks.dialplan.title
        case .stats: return L10n.main.settings.list.portalLinks.stats.title
        case .calls: return L10n.main.settings.list.portalLinks.calls.title
        case .openingHoursBasicList, .openingHoursBasicEdit: return L10n.main.settings.list.portalLinks.openingHours.title
        case .addVoicemail: return N("webView.addVoicemail.title")
        case .telephonySettings: return N("webView.telephonySettings.title")
        case .featureAnnouncements: return L10n.main.settings.featureAnnouncement.title
        case .intelligence: return N("webView.intelligence.title")
        case .addDestination: return N("webView.addDestination.title")
        }
    }

    func path(for user: User) -> String {
        let clientId = String(user.client.id)
        switch self {
        case .dialPlan: return "/dialplan/"
        case .stats: return "/stats/dashboard/"
        case .calls: return "/client/\(clientId)/call/"
        case .openingHoursBasicList: return "/client/\(user.client.uuid)/openinghoursbasic/"
        case .openingHoursBasicEdit:
            if let module = user.client.openingHoursModuleId {
                return "/client/\(user.client.uuid)/openinghoursbasic/\(module)/change/"
            }
            return "/client/\(user.client.uuid)/openinghoursbasic/"
        case .addVoicemail: return "/client/\(clientId)/voicemail/add/"
        case .telephonySettings: return "/client/\(clientId)/user/\(user.uuid)/change/#tc0=user-tab-2"
        case .featureAnnouncements: return "/featureannouncements?interface=mobile"
        case .intelligence: return "/client/\(clientId)/ai/add/"
        case .addDestination: return "/fixeddestination/add/"
        }
    }
}

struct PortalWebView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    let page: PortalPage
    var onDismiss: (() -> Void)? = nil

    @State private var url: URL?
    @State private var failed = false
    @State private var controller = WebViewController()

    var body: some View {
        NavigationStack {
            Group {
                if failed {
                    PlaceholderView(systemImage: "wifi.exclamationmark", title: "Page could not be loaded",
                                    message: "Check your connection and try again.", buttonTitle: "Try again") {
                        failed = false
                        Task { await load() }
                    }
                } else if let url {
                    WebView(url: url, controller: controller, onError: { failed = true })
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.generic.button.close) { dismiss(); onDismiss?() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { controller.goBack() } label: { Image(systemName: "chevron.left") }
                        .disabled(!controller.canGoBack)
                    Button { controller.goForward() } label: { Image(systemName: "chevron.right") }
                        .disabled(!controller.canGoForward)
                    Spacer()
                    if controller.isLoading { ProgressView() }
                    Button { controller.reload() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let user = container.session.user else { return }
        Metrics.track("web-view-opened", ["page": page.title])
        if let autoLogin = await container.session.portalAutoLoginURL(next: page.path(for: user)) {
            url = autoLogin
        } else {
            failed = true
        }
    }
}

@Observable
final class WebViewController {
    weak var webView: WKWebView?
    var canGoBack = false
    var canGoForward = false
    var isLoading = false

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
}

struct WebView: UIViewRepresentable {
    let url: URL
    let controller: WebViewController
    var onError: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        controller.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebView
        init(_ parent: WebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.controller.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.controller.isLoading = false
            parent.controller.canGoBack = webView.canGoBack
            parent.controller.canGoForward = webView.canGoForward
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.controller.isLoading = false
            if (error as NSError).code != NSURLErrorCancelled { parent.onError() }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.controller.isLoading = false
        }
    }
}
