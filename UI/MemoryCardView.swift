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
    @State private var justCopied = false

    var body: some View {
        HortCard(isSelected: isSelected, isHovering: isHovering) {
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
                                    colors: [Color.black.opacity(0.95),
                                             Color.black.opacity(0.75),
                                             Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                        }
                        .overlay(alignment: .bottom) {
                            footerView(onImage: true)
                                .background(LinearGradient(
                                    colors: [Color.clear,
                                             Color.black.opacity(0.70),
                                             Color.black.opacity(0.95)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                        }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        headerView(onImage: false)

                        Text(displayText)
                            .font(HortTypography.primary())
                            .foregroundColor(HortColors.textPrimary)
                            .lineSpacing(2)
                            .lineLimit(6)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.horizontal, HortSpacing.md)

                        footerView(onImage: false)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Layout.cardHeight, maxHeight: Theme.Layout.cardHeight)
            .overlay(
                HortColors.accentSoft
                    .opacity(isSelected ? 0.35 : 0)
                    .animation(.easeOut(duration: HortAnimation.fast), value: isSelected)
                    .allowsHitTesting(false)
            )
            .overlay(alignment: .topTrailing) { quickActions }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: HortAnimation.fast), value: isSelected)
        .animation(.easeOut(duration: HortAnimation.fast), value: isHovering)
    }

    // MARK: - Quick actions

    @ViewBuilder
    private var quickActions: some View {
        HStack(spacing: HortSpacing.xs) {
            quickActionButton(memory.isFavorite ? "star.fill" : "star",
                              tint: memory.isFavorite ? HortColors.accent : .white,
                              help: "inspector.favorite") { onFavorite?() }

            if isHovering {
                quickActionButton(justCopied ? "checkmark" : "doc.on.doc",
                                  tint: justCopied ? HortColors.accent : .white,
                                  help: "inspector.copy") {
                    onCopy?()
                    withAnimation(.easeOut(duration: 0.12)) { justCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation(.easeOut(duration: 0.2)) { justCopied = false }
                    }
                }
                quickActionButton("archivebox", help: "inspector.archive") { onArchive?() }
                quickActionButton("trash", tint: HortColors.danger, help: "inspector.delete") { onDelete?() }
            }
        }
        .padding(HortSpacing.xs)
        .background(Color.black.opacity(0.4), in: Capsule())
        .padding(HortSpacing.md)
        .transition(.opacity)
    }

    private func quickActionButton(_ icon: String, tint: Color = .white,
                                   help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: HortSizing.quickAction, height: HortSizing.quickAction)
                .background(Color.black.opacity(0.55))
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Header

    /// `onImage` cards sit on top of a photo, so the label switches to white
    /// with a dark icon chip to stay legible over bright image areas (the grey
    /// palette vanishes over white logos / bright studios).
    private func headerView(onImage: Bool) -> some View {
        let labelColor = onImage ? Color.white : HortColors.textSecondary
        let timeColor = onImage ? Color.white.opacity(0.85) : HortColors.textTertiary
        return HStack(spacing: HortSpacing.sm) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(onImage ? .white : HortColors.accent)
                .frame(width: 22, height: 22)
                .background(onImage ? Color.black.opacity(0.35) : HortColors.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: HortRadius.small, style: .continuous))

            Text(memory.type.rawValue.uppercased())
                .font(HortTypography.label(size: 10))
                .tracking(0.6)
                .lineLimit(1)
                .foregroundColor(labelColor)

            if memory.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundColor(HortColors.accent)
            }

            Spacer(minLength: HortSpacing.xs)

            Text(memory.createdAt, style: .time)
                .font(HortTypography.technical(size: 10))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundColor(timeColor)
        }
        .padding(.horizontal, HortSpacing.md)
        .padding(.top, HortSpacing.md)
        .padding(.bottom, HortSpacing.sm)
    }

    // MARK: - Footer

    /// Fixed, leading-aligned tag row: up to two chips plus a "+N" overflow, so
    /// every card's footer lines up identically regardless of tag count. (A
    /// horizontal ScrollView here clipped chips inconsistently and fought the
    /// card's drag gesture.)
    private func footerView(onImage: Bool) -> some View {
        HStack(spacing: HortSpacing.sm) {
            if !memory.tags.isEmpty {
                ForEach(memory.tags.prefix(2), id: \.self) { HortTagChip(text: $0) }
                if memory.tags.count > 2 {
                    Text("+\(memory.tags.count - 2)")
                        .font(HortTypography.label(size: 9, weight: .medium))
                        .foregroundColor(onImage ? Color.white.opacity(0.9) : HortColors.textTertiary)
                }
            } else if let app = memory.sourceApp {
                Image(systemName: "app.dashed")
                    .font(.system(size: 9))
                    .foregroundColor(onImage ? Color.white.opacity(0.9) : HortColors.textTertiary)
                Text(app)
                    .font(HortTypography.label(size: 10, weight: .medium))
                    .foregroundColor(onImage ? Color.white.opacity(0.9) : HortColors.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 34)
        .padding(.horizontal, HortSpacing.md)
        .padding(.bottom, 10)
        .clipped()
    }

    // MARK: - Helpers

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
