import AppKit
import Foundation
import UserNotifications

@MainActor
final class NotificationService: NSObject {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let seenKey = "notified_item_ids"
    private var authRequested = false

    override init() {
        super.init()
        center.delegate = self
    }

    /// Post banners for items we haven't seen before. The first time this runs
    /// against an empty seen-set we just record the IDs — otherwise a brand-new
    /// user (or a fresh install) would get a banner for every existing item.
    func notify(items: [Item]) async {
        var seen = Set(defaults.stringArray(forKey: seenKey) ?? [])
        let bootstrap = seen.isEmpty
        let newOnes = items.filter { !seen.contains($0.id) }
        guard !newOnes.isEmpty else { return }

        seen.formUnion(newOnes.map(\.id))
        defaults.set(Array(seen), forKey: seenKey)

        if bootstrap { return }

        await ensureAuthorization()
        for item in newOnes { await post(item) }
    }

    private func ensureAuthorization() async {
        guard !authRequested else { return }
        authRequested = true
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    private func post(_ item: Item) async {
        let content = UNMutableNotificationContent()
        content.title = item.subtitle ?? item.title
        content.body = item.title
        if let url = item.url {
            content.userInfo = ["url": url.absoluteString]
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: item.id, content: content, trigger: nil)
        try? await center.add(request)
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show banners even when the app is in the foreground.
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let urlString = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: urlString) else { return }
        await open(url)
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
