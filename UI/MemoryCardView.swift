import SwiftUI

/// A uniform memory tile. Every card is the same fixed size: a header row, a
/// flexible content area (image fills it, text sits top-aligned), and a footer
/// reserved for tags / source — so the grid stays a clean, even raster.
struct MemoryCardView: View {
    let memory: MemoryObject
    var isSelected: Bool = false
    var onCopy: (() -> Void)? = nil
    var onFavorite: (() -> Void)? = nil
    var onArchive: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        Group {
            if let path = imagePath, let image = NSImage(contentsOfFile: path) {
                // Color.clear defines the (flexible-width, fixed-height) cell;
                // the image fills it as an overlay and is clipped to it, so the
                // header/footer overlays always match the card width — even as
                // the column resizes.
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    )
                    .contentShape(Rectangle())
                    .clipped()
                    .overlay(alignment: .top) {
                        headerView(onImage: true)
                            .background(LinearGradient(
                                colors: [Color.black.opacity(0.9), Color.black.opacity(0.55), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                    }
                    .overlay(alignment: .bottom) {
                        footerView(onImage: true)
                            .background(LinearGradient(
                                colors: [Color.clear, Color.black.opacity(0.55), Color.black.opacity(0.9)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                    }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    headerView(onImage: false)

                    Text(displayText)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineSpacing(2)
                        .lineLimit(6)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 12)

                    footerView(onImage: false)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: Theme.Layout.cardHeight, maxHeight: Theme.Layout.cardHeight)
        .background(isHovering ? Theme.Colors.elevatedHi : Theme.Colors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cardRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 1)
        )
        .overlay(alignment: .topTrailing) { quickActions }
        .shadow(color: .black.opacity(isSelected ? 0.45 : (isHovering ? 0.35 : 0.2)),
                radius: isSelected ? 14 : (isHovering ? 10 : 5), y: 4)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isSelected)
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }

    // MARK: - Quick actions (hover)

    @ViewBuilder
    private var quickActions: some View {
        if isHovering {
            HStack(spacing: 4) {
                quickButton("doc.on.doc", help: "inspector.copy") { onCopy?() }
                quickButton(memory.isFavorite ? "star.fill" : "star", help: "inspector.favorite") { onFavorite?() }
                quickButton("archivebox", help: "inspector.archive") { onArchive?() }
                quickButton("trash", tint: Theme.Colors.danger, help: "inspector.delete") { onDelete?() }
            }
            .padding(5)
            .background(Color.black.opacity(0.4), in: Capsule())
            .padding(8)
            .transition(.opacity)
        }
    }

    private func quickButton(_ icon: String, tint: Color = .white,
                             help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 22, height: 22)
                .background(Color.black.opacity(0.55))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Header

    /// `onImage` cards sit on top of a photo, so the label switches to white
    /// with a dark icon chip to stay legible over bright image areas (the grey
    /// palette vanishes over white logos / bright studios).
    private func headerView(onImage: Bool) -> some View {
        let labelColor = onImage ? Color.white : Theme.Colors.textSecondary
        let timeColor = onImage ? Color.white.opacity(0.85) : Theme.Colors.textTertiary
        return HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(onImage ? .white : Theme.Colors.accent)
                .frame(width: 22, height: 22)
                .background(onImage ? Color.black.opacity(0.35) : Theme.Colors.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(memory.type.rawValue.uppercased())
                .font(Theme.Fonts.label(10, weight: .semibold))
                .tracking(0.6)
                .lineLimit(1)
                .foregroundColor(labelColor)

            if memory.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.Colors.accent)
            }

            Spacer(minLength: 4)

            Text(memory.createdAt, style: .time)
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundColor(timeColor)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let path = imagePath, let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .clipped()
        } else {
            Text(displayText)
                .font(.system(size: 13))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineSpacing(2)
                .lineLimit(6)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12)
        }
    }

    // MARK: - Footer

    /// Fixed, leading-aligned tag row: up to two chips plus a "+N" overflow, so
    /// every card's footer lines up identically regardless of tag count. (A
    /// horizontal ScrollView here clipped chips inconsistently and fought the
    /// card's drag gesture.)
    private func footerView(onImage: Bool) -> some View {
        HStack(spacing: 6) {
            if !memory.tags.isEmpty {
                ForEach(memory.tags.prefix(2), id: \.self) { TagChip(text: $0) }
                if memory.tags.count > 2 {
                    Text("+\(memory.tags.count - 2)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(onImage ? Color.white.opacity(0.9) : Theme.Colors.textTertiary)
                }
            } else if let app = memory.sourceApp {
                Image(systemName: "app.dashed")
                    .font(.system(size: 9))
                    .foregroundColor(onImage ? Color.white.opacity(0.9) : Theme.Colors.textTertiary)
                Text(app)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(onImage ? Color.white.opacity(0.9) : Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 34)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .clipped()
    }

    // MARK: - Helpers

    private var borderColor: Color {
        if isSelected { return Theme.Colors.accent }
        if isHovering { return Theme.Colors.borderStrong }
        return Theme.Colors.border
    }

    private var displayText: String {
        if let content = memory.content, !content.isEmpty { return content }
        return memory.type.rawValue.capitalized
    }

    /// Prefers a generated thumbnail, then falls back to the underlying image or
    /// screenshot file so previews show even before a thumbnail exists.
    private var imagePath: String? {
        if let thumb = memory.thumbnailPath, FileManager.default.fileExists(atPath: thumb) {
            return thumb
        }
        if memory.type == .image || memory.type == .screenshot || memory.type == .file,
           let content = memory.content, FileManager.default.fileExists(atPath: content) {
            return content
        }
        return nil
    }

    private var iconName: String {
        switch memory.type {
        case .text: return "text.alignleft"
        case .url: return "link"
        case .image: return "photo"
        case .screenshot: return "camera.viewfinder"
        case .file: return "doc"
        }
    }
}
