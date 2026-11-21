#!/usr/bin/env swift
// Renders the 32×32 pixel-art app icon and packs it into Resources/AppIcon.icns.
import AppKit

typealias RGBA = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)

let palette: [Character: RGBA] = [
    "K": (0x0B, 0x0F, 0x17, 0xFF),
    "B": (0x1A, 0x23, 0x33, 0xFF),
    "b": (0x24, 0x30, 0x47, 0xFF),
    "M": (0x34, 0x44, 0x62, 0xFF),
    "m": (0x4A, 0x5D, 0x82, 0xFF),
    "L": (0x6E, 0x7B, 0x91, 0xFF),
    "G": (0x3F, 0xB9, 0x50, 0xFF),
    "g": (0x23, 0x86, 0x36, 0xFF),
    "O": (0xF0, 0xA4, 0x2B, 0xFF),
    "o": (0xB5, 0x6E, 0x10, 0xFF),
    "R": (0xF8, 0x51, 0x49, 0xFF),
    "W": (0xF4, 0xF7, 0xFB, 0xFF),
    "S": (0x00, 0x00, 0x00, 0x55),
]

let size = 32
var grid = Array(repeating: Array(repeating: Character("."), count: size), count: size)

func fill(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ c: Character) {
    for y in y0...y1 { for x in x0...x1 { grid[y][x] = c } }
}

func stamp(_ x0: Int, _ y0: Int, _ rows: [String]) {
    for (dy, row) in rows.enumerated() {
        for (dx, c) in row.enumerated() where c != "." { grid[y0 + dy][x0 + dx] = c }
    }
}

let tileRange = 3...28
let cornerCut = [4, 2, 1, 1]

func inTile(_ x: Int, _ y: Int) -> Bool {
    guard tileRange.contains(x), tileRange.contains(y) else { return false }
    let fromEdgeY = min(y - tileRange.lowerBound, tileRange.upperBound - y)
    let fromEdgeX = min(x - tileRange.lowerBound, tileRange.upperBound - x)
    return fromEdgeY >= cornerCut.count || fromEdgeX >= cornerCut[fromEdgeY]
}

for y in 0..<size {
    for x in 0..<size {
        if inTile(x, y) {
            let onEdge = !(inTile(x - 1, y) && inTile(x + 1, y) && inTile(x, y - 1) && inTile(x, y + 1))
            grid[y][x] = onEdge ? "K" : "B"
        } else if y == tileRange.upperBound + 1, inTile(x, y - 1) {
            grid[y][x] = "S"
        }
    }
}

// Menu bar strip with tray status dots.
fill(6, 6, 25, 8, "M")
fill(6, 6, 25, 6, "m")
grid[7][19] = "G"
grid[7][21] = "O"
grid[7][23] = "R"
fill(8, 7, 13, 7, "L")

// Pipeline: two passed jobs feeding a running one.
let passed = [
    ".GGGG.",
    "GGGGGG",
    "GGGGWG",
    "GWGWGG",
    "GGWGGG",
    ".gggg.",
]
let running = [
    ".OOOO.",
    "OOWWOO",
    "OWOOOO",
    "OWOOWO",
    "OOWWOO",
    ".oooo.",
]
stamp(5, 13, passed)
stamp(13, 13, passed)
stamp(21, 13, running)
fill(11, 15, 12, 16, "L")
fill(19, 15, 20, 16, "L")

// Progress bar.
fill(6, 22, 25, 24, "K")
fill(7, 23, 18, 23, "G")
fill(19, 23, 24, 23, "b")

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let scale = Double(pixels) / Double(size)
    for py in 0..<pixels {
        for px in 0..<pixels {
            let c = grid[Int(Double(py) / scale)][Int(Double(px) / scale)]
            let rgba = palette[c] ?? (0, 0, 0, 0)
            var values = [Int(rgba.r), Int(rgba.g), Int(rgba.b), Int(rgba.a)]
            rep.setPixel(&values, atX: px, y: py)
        }
    }
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try render(pixels: 1024).write(to: root.appendingPathComponent("Resources/AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print("Wrote Resources/AppIcon.icns")
