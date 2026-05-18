#!/usr/bin/env swift
// Renders Resources/AppIcon.icns from a single SF Symbol on a colored squircle.
// Run from the repo root: `swift scripts/generate-icon.swift`
import AppKit
import Foundation

// MARK: - Design constants
let symbolName = "waveform.path.ecg"
let backgroundHex = "1E40AF"           // cobalt blue
let symbolColor = NSColor.white
let symbolWeight: NSFont.Weight = .semibold
let symbolScale: CGFloat = 0.58        // fraction of icon side
let cornerRatio: CGFloat = 0.2237      // approximates the macOS squircle corner

// MARK: - Helpers
func nsColor(hex: String) -> NSColor {
    var rgb: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&rgb)
    let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
    let g = CGFloat((rgb >> 8)  & 0xFF) / 255.0
    let b = CGFloat( rgb        & 0xFF) / 255.0
    return NSColor(red: r, green: g, blue: b, alpha: 1)
}

func renderIcon(side: Int) -> Data {
    let dim = CGFloat(side)
    let image = NSImage(size: NSSize(width: dim, height: dim))
    image.lockFocus()

    let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: dim, height: dim),
                          xRadius: dim * cornerRatio,
                          yRadius: dim * cornerRatio)
    nsColor(hex: backgroundHex).setFill()
    bg.fill()

    let pointSize = dim * symbolScale
    let baseConfig = NSImage.SymbolConfiguration(pointSize: pointSize, weight: symbolWeight)
    let paletteConfig = NSImage.SymbolConfiguration(paletteColors: [symbolColor])
    let config = baseConfig.applying(paletteConfig)

    guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
        FileHandle.standardError.write(Data("Failed to load SF Symbol \(symbolName)\n".utf8))
        exit(1)
    }

    let sz = symbol.size
    let rect = NSRect(x: (dim - sz.width) / 2,
                      y: (dim - sz.height) / 2,
                      width: sz.width, height: sz.height)
    symbol.draw(in: rect)

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("PNG encode failed at \(side)x\(side)\n".utf8))
        exit(1)
    }
    return png
}

// MARK: - Emit iconset and run iconutil
let entries: [(name: String, side: Int)] = [
    ("icon_16x16.png",       16),
    ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",       32),
    ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png",1024),
]

let cwd = FileManager.default.currentDirectoryPath
let iconsetDir = URL(fileURLWithPath: cwd).appendingPathComponent("build/AppIcon.iconset")
let icnsOut    = URL(fileURLWithPath: cwd).appendingPathComponent("Resources/AppIcon.icns")

let fm = FileManager.default
try? fm.removeItem(at: iconsetDir)
try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

for (name, side) in entries {
    let url = iconsetDir.appendingPathComponent(name)
    try renderIcon(side: side).write(to: url)
    print("wrote \(name)  (\(side)×\(side))")
}

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsOut.path]
try proc.run()
proc.waitUntilExit()
if proc.terminationStatus != 0 {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(Int32(proc.terminationStatus))
}

print("Wrote \(icnsOut.path)")
