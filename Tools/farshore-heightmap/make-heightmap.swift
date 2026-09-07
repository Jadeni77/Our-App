#!/usr/bin/env swift
// Produces the FIRST DRAFT of an authored island, once.
//
// The committed PNG is the source of truth, not this script (F2). Open it in
// any image editor and paint — a cove, a ridge, a flat place for a camp. Never
// regenerate over hand edits; if you need a different island, make a new file.
//
//   swift Tools/farshore-heightmap/make-heightmap.swift out.png
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 512
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1
              ? CommandLine.arguments[1] : "farshore-01.png")

func hash(_ x: Int, _ y: Int) -> Double {
    var h = UInt64(bitPattern: Int64(x &* 374_761_393 &+ y &* 668_265_263 &+ 20_260_902))
    h = (h ^ (h >> 13)) &* 1_274_126_177
    return Double((h ^ (h >> 16)) % 100_000) / 100_000.0
}
func smooth(_ x: Double, _ y: Double) -> Double {
    let xi = Int(floor(x)), yi = Int(floor(y))
    let xf = x - Double(xi), yf = y - Double(yi)
    let u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf)
    let a = hash(xi, yi), b = hash(xi + 1, yi), c = hash(xi, yi + 1), d = hash(xi + 1, yi + 1)
    return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v
}

var bytes = [UInt8](repeating: 0, count: size * size)
for y in 0..<size {
    for x in 0..<size {
        let nx = Double(x) / Double(size) - 0.5
        let ny = Double(y) / Double(size) - 0.5
        // Radial falloff makes it an island rather than a landscape.
        let falloff = max(0, cos(min(hypot(nx, ny) * 2.0, 1.0) * .pi / 2))
        let n = smooth(Double(x) * 0.018, Double(y) * 0.018) * 0.6
              + smooth(Double(x) * 0.045, Double(y) * 0.045) * 0.3
              + smooth(Double(x) * 0.11,  Double(y) * 0.11)  * 0.1
        bytes[y * size + x] = UInt8(max(0, min(255, n * pow(falloff, 1.3) * 300)))
    }
}

let space = CGColorSpaceCreateDeviceGray()
// `CGContext(data: &bytes, ...)` would only guarantee the pointer for the
// duration of that one call, but the context keeps writing through it for as
// long as it lives — including inside `makeImage()`, called below. That is
// technically undefined behaviour even though it usually "works". Doing the
// whole write inside `withUnsafeMutableBytes` keeps every use of the pointer
// inside the one closure Swift actually promises it valid for.
bytes.withUnsafeMutableBytes { raw in
    guard let ctx = CGContext(data: raw.baseAddress, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: size, space: space,
                              bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
        fatalError("could not create bitmap context")
    }
    guard let image = ctx.makeImage() else {
        fatalError("could not render heightmap image")
    }
    guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("could not create image destination at \(out.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}
print("wrote \(out.path)")
