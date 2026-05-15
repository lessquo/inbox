import SwiftUI
import AppKit

struct ItemRow: View {
    @Environment(ItemStore.self) private var store
    let item: Item

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(for: item.sourceId))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let reason = item.reason {
                        Text("·").font(.caption).foregroundStyle(.secondary)
                        Text(reason.replacingOccurrences(of: "_", with: " "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(item.updatedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                Task { await store.markDone(item) }
            } label: {
                Image(systemName: "checkmark.circle")
                    .imageScale(.large)
            }
            .buttonStyle(.borderless)
            .help("Mark as done")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = item.url { NSWorkspace.shared.open(url) }
        }
    }

    private func icon(for sourceId: String) -> String {
        switch sourceId {
        case "github": return "chevron.left.forwardslash.chevron.right"
        default: return "tray"
        }
    }
}
