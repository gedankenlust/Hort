#!/usr/bin/env bash
#
# Generates the Hort app icon (Assets/AppIcon.icns) from scratch:
# a cyan stacked-layers mark on a dark graphite squircle, matching the
# in-app wordmark. Reproducible — re-run any time the brand changes.
#
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
MASTER="$WORK/icon_1024.png"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

echo "▶ Rendering master 1024×1024…"
cat > "$WORK/render.swift" <<'SWIFT'
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

let rect = NSRect(x: 0, y: 0, width: size, height: size)
let squircle = NSBezierPath(roundedRect: rect, xRadius: 229, yRadius: 229)
squircle.addClip()

// Graphite gradient background.
let top = NSColor(srgbRed: 0x16/255, green: 0x1D/255, blue: 0x2A/255, alpha: 1)
let bottom = NSColor(srgbRed: 0x09/255, green: 0x0C/255, blue: 0x12/255, alpha: 1)
NSGradient(colors: [top, bottom])!.draw(in: rect, angle: -90)

// Subtle top sheen.
NSGradient(colors: [NSColor.white.withAlphaComponent(0.06), NSColor.clear])!
    .draw(in: NSRect(x: 0, y: size * 0.6, width: size, height: size * 0.4), angle: -90)

// Cyan stacked-layers mark.
let accent = NSColor(srgbRed: 0x32/255, green: 0xD2/255, blue: 0xE0/255, alpha: 1)
let config = NSImage.SymbolConfiguration(pointSize: 560, weight: .semibold)
if let base = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    // Tint the (template) symbol to the accent colour.
    let tinted = NSImage(size: base.size)
    tinted.lockFocus()
    accent.set()
    let br = NSRect(origin: .zero, size: base.size)
    base.draw(in: br)
    br.fill(using: .sourceAtop)
    tinted.unlockFocus()

    let target = NSRect(x: (size - tinted.size.width) / 2,
                        y: (size - tinted.size.height) / 2,
                        width: tinted.size.width, height: tinted.size.height)

    let shadow = NSShadow()
    shadow.shadowColor = accent.withAlphaComponent(0.55)
    shadow.shadowBlurRadius = 48
    shadow.shadowOffset = .zero
    shadow.set()
    tinted.draw(in: target)
}

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to encode icon\n", stderr); exit(1)
}
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT
swift "$WORK/render.swift" "$MASTER"

echo "▶ Building iconset…"
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
    set -- $spec
    sips -z "$1" "$1" "$MASTER" --out "$ICONSET/icon_$2.png" >/dev/null
done

echo "▶ Packing AppIcon.icns…"
mkdir -p Assets
iconutil -c icns "$ICONSET" -o Assets/AppIcon.icns
rm -rf "$WORK"
echo "✔ Wrote Assets/AppIcon.icns"
