import Foundation

struct Item: Identifiable, Hashable, Sendable {
    let id: String           // globally unique: "<sourceId>:<extId>"
    let sourceId: String     // e.g. "github"
    let extId: String   // provider-scoped id (e.g. GitHub thread id)
    let title: String
    let subtitle: String?    // e.g. repo full name
    let reason: String?      // e.g. "mention", "review_requested"
    let updatedAt: Date
    let url: URL?
    var isRead: Bool
}
