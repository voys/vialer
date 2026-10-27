import SwiftUI

/// "No internet connection" card, matching the Flutter ConnectivityAlert.
struct ConnectivityBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text(L10n.connectivity.noConnection.title).font(.subheadline.bold())
        }
        .foregroundStyle(.white)
        .bannerCard(Theme.red)
    }
}

/// Builds an A–Z strip that scrolls a list to the matching section.
struct SectionIndex: View {
    let keys: [String]
    let proxy: ScrollViewProxy
    @State private var dragging = false

    var body: some View {
        VStack(spacing: 2) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 20, height: 14)
            }
        }
        .padding(.vertical, 6)
        .background(dragging ? Theme.grey7.opacity(0.9) : Color.clear)
        .clipShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragging = true
                    let rowHeight: CGFloat = 16
                    let index = Int((value.location.y - 6) / rowHeight)
                    guard keys.indices.contains(index) else { return }
                    proxy.scrollTo(keys[index], anchor: .top)
                }
                .onEnded { _ in dragging = false }
        )
    }
}
