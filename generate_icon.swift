#!/usr/bin/swift
import AppKit
import CoreGraphics

// MARK: - Draw 1024x1024 icon

func makeIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let s = size
    let rect = CGRect(x: 0, y: 0, width: s, height: s)

    // — Background: blue → indigo gradient, macOS rounded corners —
    let radius = s * 0.2237
    let bgPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    let cs = CGColorSpaceCreateDeviceRGB()
    let gradColors = [
        CGColor(red: 0.05, green: 0.48, blue: 0.98, alpha: 1),  // bright blue
        CGColor(red: 0.34, green: 0.17, blue: 0.88, alpha: 1),  // indigo
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: cs, colors: gradColors, locations: [0, 1]) {
        ctx.drawLinearGradient(gradient,
            start: CGPoint(x: 0, y: s),
            end: CGPoint(x: s, y: 0),
            options: [])
    }

    // — Subtle inner shadow at top for depth —
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let shimmerColors = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.18),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    ] as CFArray
    if let shimmer = CGGradient(colorsSpace: cs, colors: shimmerColors, locations: [0, 1]) {
        ctx.drawLinearGradient(shimmer,
            start: CGPoint(x: s * 0.5, y: s),
            end: CGPoint(x: s * 0.5, y: s * 0.5),
            options: [])
    }
    ctx.restoreGState()

    // — Phone body —
    let pw: CGFloat = s * 0.38      // phone width
    let ph: CGFloat = s * 0.62      // phone height
    let px: CGFloat = (s - pw) / 2
    let py: CGFloat = (s - ph) / 2
    let pr: CGFloat = pw * 0.22     // phone corner radius

    let phonePath = CGPath(roundedRect: CGRect(x: px, y: py, width: pw, height: ph),
                           cornerWidth: pr, cornerHeight: pr, transform: nil)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.97))
    ctx.addPath(phonePath)
    ctx.fillPath()

    // — Phone screen —
    let si: CGFloat = pw * 0.10
    let screenRect = CGRect(x: px + si, y: py + pw * 0.3,
                            width: pw - si * 2, height: ph - pw * 0.38 - si)
    let screenPath = CGPath(roundedRect: screenRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
    ctx.setFillColor(CGColor(red: 0.07, green: 0.47, blue: 0.95, alpha: 1))
    ctx.addPath(screenPath)
    ctx.fillPath()

    // — Screen shine overlay —
    ctx.saveGState()
    ctx.addPath(screenPath)
    ctx.clip()
    let shineColors = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.15),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    ] as CFArray
    if let shine = CGGradient(colorsSpace: cs, colors: shineColors, locations: [0, 1]) {
        ctx.drawLinearGradient(shine,
            start: CGPoint(x: screenRect.midX, y: screenRect.maxY),
            end: CGPoint(x: screenRect.midX, y: screenRect.midY),
            options: [])
    }
    ctx.restoreGState()

    // — Earpiece —
    let epW = pw * 0.35
    let epH = ph * 0.028
    let epX = px + (pw - epW) / 2
    let epY = py + ph - pw * 0.2
    ctx.setFillColor(CGColor(red: 0.78, green: 0.78, blue: 0.82, alpha: 1))
    let epPath = CGPath(roundedRect: CGRect(x: epX, y: epY, width: epW, height: epH),
                        cornerWidth: epH / 2, cornerHeight: epH / 2, transform: nil)
    ctx.addPath(epPath)
    ctx.fillPath()

    // — Home button dot —
    let hbR = pw * 0.075
    let hbX = px + pw / 2 - hbR
    let hbY = py + pw * 0.08
    ctx.setFillColor(CGColor(red: 0.82, green: 0.82, blue: 0.86, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: hbX, y: hbY, width: hbR * 2, height: hbR * 2))

    // — Wireless arcs (bottom-right of icon, white) —
    let wCx = s * 0.72
    let wCy = s * 0.22
    let arcWidths: [CGFloat] = [2.5, 2.0, 1.5]
    let arcRadii: [CGFloat]  = [s * 0.13, s * 0.09, s * 0.05]
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
    ctx.setLineCap(.round)

    for (i, r) in arcRadii.enumerated() {
        ctx.setLineWidth(arcWidths[i] * s / 512)
        ctx.addArc(center: CGPoint(x: wCx, y: wCy),
                   radius: r,
                   startAngle: .pi * 0.15,
                   endAngle: .pi * 0.85,
                   clockwise: false)
        ctx.strokePath()
    }
    // Dot at arc center
    let dotR = s * 0.022
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
    ctx.fillEllipse(in: CGRect(x: wCx - dotR, y: wCy - dotR, width: dotR * 2, height: dotR * 2))

    image.unlockFocus()
    return image
}

// MARK: - Save PNG

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("❌ Failed to encode \(path)")
        return
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("✅ \(path)")
    } catch {
        print("❌ \(error) → \(path)")
    }
}

// MARK: - Generate all sizes

let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

let sizes: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

print("Generating icons in: \(outputDir)")
for (px, filename) in sizes {
    let img = makeIcon(size: CGFloat(px))
    savePNG(img, to: "\(outputDir)/\(filename)")
}
print("Done.")
