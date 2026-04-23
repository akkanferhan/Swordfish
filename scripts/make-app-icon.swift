#!/usr/bin/env swift
//
// Generates the full AppIcon.appiconset for Swordfish.
// Pure CoreGraphics / AppKit — no external assets required.
//
// Usage:  swift scripts/make-app-icon.swift <output-dir>
//
// The output dir is typically `Swordfish/Resources/Assets.xcassets/AppIcon.appiconset`.

import Foundation
import AppKit
import CoreGraphics

enum IconGen {

    // MARK: - Background

    static func drawBackground(_ ctx: CGContext, size: CGFloat) {
        let corner = size * 0.22    // macOS icon "squircle" radius
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: corner,
            cornerHeight: corner,
            transform: nil
        )
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()

        // Linear gradient: deep navy at bottom → ocean blue → cyan at top
        let cs = CGColorSpaceCreateDeviceRGB()
        let stops: [CGColor] = [
            CGColor(srgbRed: 0.04, green: 0.18, blue: 0.40, alpha: 1),
            CGColor(srgbRed: 0.06, green: 0.46, blue: 0.78, alpha: 1),
            CGColor(srgbRed: 0.18, green: 0.72, blue: 0.92, alpha: 1),
        ]
        let gradient = CGGradient(
            colorsSpace: cs,
            colors: stops as CFArray,
            locations: [0, 0.55, 1]
        )!
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 0, y: size),
            options: []
        )

        // Subtle top-right radial highlight for depth
        let highlight = CGGradient(
            colorsSpace: cs,
            colors: [
                CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22),
                CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
            ] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawRadialGradient(
            highlight,
            startCenter: CGPoint(x: size * 0.75, y: size * 0.80),
            startRadius: 0,
            endCenter: CGPoint(x: size * 0.75, y: size * 0.80),
            endRadius: size * 0.55,
            options: []
        )

        ctx.restoreGState()
    }

    // MARK: - Swordfish silhouette

    static func drawSwordfish(_ ctx: CGContext, size: CGFloat) {
        // Unit space: 0...1 with Y down (standard design coords), we flip to CG.
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * size, y: (1 - y) * size)
        }

        let body = CGMutablePath()
        // Start at the bill tip (right-most point)
        body.move(to: pt(0.94, 0.50))

        // Upper bill edge sloping back to the head
        body.addLine(to: pt(0.62, 0.455))

        // Forehead curve up to the base of the dorsal fin
        body.addCurve(
            to: pt(0.50, 0.370),
            control1: pt(0.57, 0.430),
            control2: pt(0.54, 0.400)
        )

        // Dorsal fin: up to peak then back down
        body.addQuadCurve(to: pt(0.44, 0.170), control: pt(0.46, 0.260))
        body.addLine(to: pt(0.38, 0.400))

        // Back ridge curving to the tail peduncle
        body.addCurve(
            to: pt(0.18, 0.440),
            control1: pt(0.32, 0.410),
            control2: pt(0.24, 0.430)
        )

        // Upper tail fin tip
        body.addLine(to: pt(0.06, 0.300))
        body.addLine(to: pt(0.02, 0.350))
        // Tail fin inner notch (forked caudal)
        body.addLine(to: pt(0.12, 0.500))
        // Lower tail fin tip
        body.addLine(to: pt(0.02, 0.650))
        body.addLine(to: pt(0.06, 0.700))

        // Belly back toward the pelvic fin
        body.addCurve(
            to: pt(0.30, 0.580),
            control1: pt(0.14, 0.580),
            control2: pt(0.22, 0.580)
        )

        // Pelvic fin (small triangular fin on the underside)
        body.addLine(to: pt(0.34, 0.720))
        body.addLine(to: pt(0.40, 0.580))

        // Lower belly arc to the chin / lower bill base
        body.addCurve(
            to: pt(0.62, 0.545),
            control1: pt(0.48, 0.580),
            control2: pt(0.55, 0.570)
        )

        // Lower bill edge back to the bill tip
        body.addLine(to: pt(0.94, 0.50))
        body.closeSubpath()

        // Soft drop shadow
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -size * 0.008),
            blur: size * 0.015,
            color: CGColor(gray: 0, alpha: 0.28)
        )
        ctx.setFillColor(CGColor(gray: 0.98, alpha: 1.0))
        ctx.addPath(body)
        ctx.fillPath()
        ctx.restoreGState()

        // Eye (tiny dark dot near the head)
        ctx.saveGState()
        ctx.setFillColor(CGColor(srgbRed: 0.06, green: 0.18, blue: 0.32, alpha: 0.95))
        let eyeR = size * 0.018
        let eye = CGRect(
            x: 0.555 * size - eyeR,
            y: (1 - 0.460) * size - eyeR,
            width: eyeR * 2,
            height: eyeR * 2
        )
        ctx.addEllipse(in: eye)
        ctx.fillPath()
        ctx.restoreGState()

        // Subtle bill highlight line along the top edge of the bill
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.35))
        ctx.setLineWidth(max(1, size * 0.004))
        ctx.setLineCap(.round)
        let highlight = CGMutablePath()
        highlight.move(to: pt(0.66, 0.460))
        highlight.addLine(to: pt(0.90, 0.500))
        ctx.addPath(highlight)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Render

    static func renderPNG(size: Int, to url: URL) throws {
        let s = CGFloat(size)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 32
        )!

        guard let gctx = NSGraphicsContext(bitmapImageRep: rep) else {
            fatalError("couldn't create graphics context")
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gctx
        let ctx = gctx.cgContext
        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)

        drawBackground(ctx, size: s)
        drawSwordfish(ctx, size: s)

        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else {
            fatalError("couldn't encode PNG")
        }
        try data.write(to: url)
    }
}

// MARK: - Contents.json

func writeContentsJSON(to url: URL) throws {
    let json = """
    {
      "images" : [
        { "filename" : "icon_16x16.png",       "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
        { "filename" : "icon_16x16@2x.png",    "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
        { "filename" : "icon_32x32.png",       "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
        { "filename" : "icon_32x32@2x.png",    "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
        { "filename" : "icon_128x128.png",     "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
        { "filename" : "icon_128x128@2x.png",  "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
        { "filename" : "icon_256x256.png",     "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
        { "filename" : "icon_256x256@2x.png",  "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
        { "filename" : "icon_512x512.png",     "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
        { "filename" : "icon_512x512@2x.png",  "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }
    """
    try json.write(to: url, atomically: true, encoding: .utf8)
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count == 2 else {
    print("usage: make-app-icon.swift <output-dir>")
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let sizes: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, size) in sizes {
    let url = outDir.appendingPathComponent(name)
    try IconGen.renderPNG(size: size, to: url)
    print("✓ \(name) (\(size)x\(size))")
}

try writeContentsJSON(to: outDir.appendingPathComponent("Contents.json"))
print("✓ Contents.json")
print("done → \(outDir.path)")
