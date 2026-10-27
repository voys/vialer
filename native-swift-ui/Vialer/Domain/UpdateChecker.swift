import Foundation
import Observation

struct StoreUpdate: Equatable {
    let version: String
    let storeURL: URL
}

/// Shows release notes after an update and a reminder when the App Store has a newer version,
/// mirroring the Flutter AppUpdateChecker and GentleUpdateReminder.
@MainActor
@Observable
final class UpdateChecker {
    var showReleaseNotes = false
    private(set) var storeUpdate: StoreUpdate?
    var showStoreReminder = false

    private let store = LocalStore.shared
    private var lastStoreCheck: Date?

    func check() {
        checkReleaseNotes()
        Task { await checkAppStore() }
    }

    private func checkReleaseNotes() {
        let current = BuildInfo.version
        let previous = store.string(.lastInstalledVersion)
        store.setString(current, for: .lastInstalledVersion)
        guard let previous, previous != current else { return }
        AppLog.info("Updated from \(previous) to \(current), showing release notes")
        showReleaseNotes = true
    }

    /// Lines for this platform, with the `ios:` / `android:` prefixes applied and removed.
    var releaseNotesForPlatform: [String] {
        let raw = Locale.current.language.languageCode?.identifier == "nl" && !ReleaseNotes.dutch.isEmpty
            ? ReleaseNotes.dutch
            : ReleaseNotes.english
        return raw.split(separator: "\n").map(String.init)
            .filter { !$0.lowercased().contains("android:") }
            .map { $0.replacingOccurrences(of: "(?i)ios:", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.hasPrefix("-") ? "•" + $0.dropFirst() : $0 }
    }

    private func checkAppStore() async {
        if let lastStoreCheck, Date().timeIntervalSince(lastStoreCheck) < 3600 { return }
        lastStoreCheck = Date()
        guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(Brand.bundleId)") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = (json["results"] as? [[String: Any]])?.first,
              let version = result["version"] as? String,
              let storeURL = (result["trackViewUrl"] as? String).flatMap(URL.init) else { return }
        guard Self.isNewer(version, than: BuildInfo.version) else { return }
        AppLog.info("App Store has version \(version), installed is \(BuildInfo.version)")
        storeUpdate = StoreUpdate(version: version, storeURL: storeURL)
        showStoreReminder = true
        Task {
            try? await Task.sleep(for: .seconds(15))
            showStoreReminder = false
        }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").compactMap { Int($0) }
        let b = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
