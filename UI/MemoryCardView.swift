import SwiftUI

/// A uniform memory tile. Every card is the same fixed size: a header row, a
/// flexible content area (image fills it, text sits top-aligned), and a footer
/// reserved for tags / source — so the grid stays a clean, even raster.
struct MemoryCardView: View {
    let memory: MemoryObject
    var isSelected: Bool = false
    var boardColor: Color? = nil
    var onCopy: (() -> Void)? = nil
    var onFavorite: (() -> Void)? = nil
    var onArchive: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onTagClick: ((String) -> Void)? = nil

    @State private var isHovering = false
    @State private var justCopied = false
    @State private var loadedImage: NSImage?

    var body: some View {
        HortCard(isSelected: isSelected, isHovering: isHovering) {
            Group {
                if let image = loadedImage {
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

                        cardContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.horizontal, HortSpacing.md)

                        footerView(onImage: false)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: HortSizing.cardHeight, maxHeight: HortSizing.cardHeight)
            .overlay(
                HortColors.accentSoft
                    .opacity(isSelected ? 0.35 : 0)
                    .animation(.easeOut(duration: HortAnimation.fast), value: isSelected)
                    .allowsHitTesting(false)
            )
            .overlay(alignment: .topTrailing) { quickActions }
            .overlay(alignment: .leading) {
                if let color = boardColor {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color)
                        .frame(width: 3, height: 24)
                        .padding(.leading, 3)
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: HortAnimation.fast), value: isSelected)
        .animation(.easeOut(duration: HortAnimation.fast), value: isHovering)
        .task(id: imagePath) {
            guard let path = imagePath else { loadedImage = nil; return }
            if let cached = ImageCache.shared[path] { loadedImage = cached; return }
            let img = await Task.detached { NSImage(contentsOfFile: path) }.value
            ImageCache.shared[path] = img
            loadedImage = img
        }
    }

    // MARK: - Quick actions

    @ViewBuilder
    private var quickActions: some View {
        if isHovering {
            HStack(spacing: HortSpacing.xs) {
                quickActionButton(memory.isFavorite ? "star.fill" : "star",
                                  tint: memory.isFavorite ? HortColors.accent : .white,
                                  help: "inspector.favorite") { onFavorite?() }
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
            .padding(HortSpacing.xs)
            .background(Color.black.opacity(0.4), in: Capsule())
            .padding(HortSpacing.md)
            .transition(.opacity)
        }
    }

    private func quickActionButton(_ icon: String, tint: Color = .white,
                                   help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(HortTypography.label(size: 11))
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
        let tint = onImage ? Color.white : iconTint
        return HStack(spacing: HortSpacing.sm) {
            Image(systemName: iconName)
                .font(HortTypography.label(size: 11))
                .foregroundColor(tint)
                .frame(width: 22, height: 22)
                .background(onImage ? Color.black.opacity(0.35) : tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: HortRadius.small, style: .continuous))

            Text(memory.type.rawValue.uppercased())
                .font(HortTypography.label(size: 10))
                .tracking(0.6)
                .lineLimit(1)
                .foregroundColor(labelColor)

            if memory.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
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
                ForEach(memory.tags.prefix(2), id: \.self) { tag in
                    Button { onTagClick?(tag) } label: { HortTagChip(text: tag) }
                        .buttonStyle(.plain)
                }
                if memory.tags.count > 2 {
                    Text("+\(memory.tags.count - 2)")
                        .font(HortTypography.label(size: 9, weight: .medium))
                        .foregroundColor(onImage ? Color.white.opacity(0.9) : HortColors.textTertiary)
                }
            } else if let app = memory.sourceApp {
                Image(systemName: "app.dashed")
                    .font(HortTypography.label(size: 9))
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

    // MARK: - Content display

    @ViewBuilder
    private var cardContent: some View {
        if memory.type == .url, let content = memory.content, let url = URL(string: content) {
            urlDisplay(url, raw: content)
        } else {
            titleBodyDisplay
        }
    }

    @ViewBuilder
    private var titleBodyDisplay: some View {
        let text = displayText
        let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        VStack(alignment: .leading, spacing: 2) {
            Text(String(lines[0]))
                .font(HortTypography.primary(weight: .semibold))
                .foregroundColor(HortColors.textPrimary)
                .lineLimit(1)
            if lines.count > 1, !lines[1].isEmpty {
                Text(String(lines[1]))
                    .font(HortTypography.primary())
                    .foregroundColor(HortColors.textSecondary)
                    .lineSpacing(2)
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private func urlDisplay(_ url: URL, raw: String) -> some View {
        VStack(alignment: .leading, spacing: HortSpacing.xs) {
            HStack(spacing: HortSpacing.xs) {
                Image(systemName: "arrow.up.right.square")
                    .font(HortTypography.label(size: 10))
                    .foregroundColor(HortColors.accent)
                Text(url.host ?? raw)
                    .font(HortTypography.primary(weight: .semibold))
                    .foregroundColor(HortColors.textPrimary)
                    .lineLimit(1)
            }
            if !url.path.isEmpty, url.path != "/" {
                Text(url.path)
                    .font(HortTypography.technical(size: HortTypography.Size.caption))
                    .foregroundColor(HortColors.textTertiary)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Helpers

    private var displayText: String {
        if let content = memory.content, !content.isEmpty { return content }
        return memory.type.rawValue.capitalized
    }

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

    private var iconTint: Color {
        switch memory.type {
        case .text:       return HortColors.accent
        case .url:        return HortColors.info
        case .image:      return HortColors.success
        case .screenshot: return HortColors.warning
        case .file:       return HortColors.textSecondary
        }
    }
}

final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private var cache = NSCache<NSString, NSImage>()
    private init() { cache.countLimit = 200 }
    subscript(path: String) -> NSImage? {
        get { cache.object(forKey: path as NSString) }
        set {
            if let img = newValue { cache.setObject(img, forKey: path as NSString) }
            else { cache.removeObject(forKey: path as NSString) }
        }
    }
}
