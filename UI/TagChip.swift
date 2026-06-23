import SwiftUI

/// A small tag pill, optionally removable.
struct TagChip: View {
    let text: String
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundColor(Theme.Colors.accent)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Theme.Colors.accentSoft)
        .clipShape(Capsule())
    }
}

/// Tag normalisation helpers: tags are lowercased, trimmed, de-duplicated.
enum Tag {
    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}
