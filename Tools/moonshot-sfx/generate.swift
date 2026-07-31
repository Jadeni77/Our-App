#!/usr/bin/env swift
// Moonshot SFX generator — every sound is pure synthesis, so provenance is
// this file (principle 9: original assets only). Rerun to regenerate:
//
//   swift Tools/moonshot-sfx/generate.swift OurApp/Modules/Moonshot/Resources/SFX
//
// Committed alongside the .caf files it produces; tweak a recipe, rerun,
// commit both.

import AVFoundation
import Foundation

let sampleRate = 44100.0

func writeCAF(_ name: String, _ samples: [Float], to directory: URL) throws {
    let url = directory.appendingPathComponent("\(name).caf")
    try? FileManager.default.removeItem(at: url)
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                               channels: 1, interleaved: false)!
    let file = try AVAudioFile(forWriting: url, settings: format.settings,
                               commonFormat: .pcmFormatFloat32, interleaved: false)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
    buffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { source in
        buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
    }
    try file.write(from: buffer)
    print("wrote \(name).caf (\(String(format: "%.2f", Double(samples.count) / sampleRate))s)")
}

func seconds(_ duration: Double) -> Int { Int(duration * sampleRate) }

/// Sine with optional exponential pitch sweep and exponential amplitude decay.
func tone(from startHz: Double, to endHz: Double? = nil, duration: Double,
          amplitude: Double = 0.6, decay: Double = 6) -> [Float] {
    let count = seconds(duration)
    var phase = 0.0
    return (0..<count).map { i in
        let t = Double(i) / Double(count)
        let hz = endHz.map { startHz * pow($0 / startHz, t) } ?? startHz
        phase += 2 * .pi * hz / sampleRate
        return Float(sin(phase) * amplitude * exp(-decay * t))
    }
}

/// Deterministic RNG (SplitMix64): rerunning the script reproduces the
/// committed bytes exactly, so assets ⇄ generator stay verifiable and a
/// no-change rerun never churns binary diffs.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// White noise burst with exponential decay and a crude brightness filter
/// (1 = raw noise; higher = darker, via a simple running average).
func noise(duration: Double, amplitude: Double = 0.5, decay: Double = 10,
           smooth: Int = 1, seed: UInt64 = 0x5EED) -> [Float] {
    let count = seconds(duration)
    var rng = SeededRNG(seed: seed)
    var raw = (0..<count).map { _ in Double.random(in: -1...1, using: &rng) }
    if smooth > 1 {
        var window = [Double](repeating: 0, count: smooth)
        var index = 0, sum = 0.0
        raw = raw.map { sample in
            sum -= window[index]; window[index] = sample; sum += sample
            index = (index + 1) % smooth
            return sum / Double(smooth)
        }
    }
    return raw.enumerated().map { i, sample in
        let t = Double(i) / Double(count)
        return Float(sample * amplitude * exp(-decay * t))
    }
}

func mix(_ layers: [Float]...) -> [Float] {
    let length = layers.map(\.count).max() ?? 0
    var out = [Float](repeating: 0, count: length)
    for layer in layers {
        for (i, sample) in layer.enumerated() { out[i] += sample }
    }
    let peak = out.map(abs).max() ?? 1
    return peak > 0.95 ? out.map { $0 / peak * 0.9 } : out
}

func delayed(_ samples: [Float], by delay: Double) -> [Float] {
    [Float](repeating: 0, count: seconds(delay)) + samples
}

// MARK: Recipes

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "OurApp/Modules/Moonshot/Resources/SFX", isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

// The fling: a rubber-band sweep down as tension releases.
try writeCAF("release", tone(from: 300, to: 90, duration: 0.18, amplitude: 0.55, decay: 5), to: out)

// The pull: a low creak — slow noise over a quiet groan.
try writeCAF("stretch", mix(
    tone(from: 82, duration: 0.3, amplitude: 0.18, decay: 2),
    noise(duration: 0.3, amplitude: 0.08, decay: 2, smooth: 24)), to: out)

// Impacts: crystal shatters bright, moonwood knocks, meteorstone booms.
try writeCAF("impact-crystal", mix(
    noise(duration: 0.25, amplitude: 0.35, decay: 14, smooth: 1),
    tone(from: 2793, duration: 0.22, amplitude: 0.16, decay: 16),
    tone(from: 3322, duration: 0.20, amplitude: 0.13, decay: 18),
    tone(from: 3951, duration: 0.18, amplitude: 0.10, decay: 20)), to: out)
try writeCAF("impact-moonwood", mix(
    tone(from: 120, duration: 0.22, amplitude: 0.55, decay: 12),
    noise(duration: 0.1, amplitude: 0.2, decay: 22, smooth: 6)), to: out)
try writeCAF("impact-stone", mix(
    tone(from: 70, duration: 0.35, amplitude: 0.6, decay: 8),
    noise(duration: 0.12, amplitude: 0.12, decay: 20, smooth: 14)), to: out)

// A gloom pops: a cheeky rising chirp.
try writeCAF("gloom-pop", tone(from: 500, to: 900, duration: 0.12, amplitude: 0.5, decay: 4), to: out)

// The win chime: an E-major arpeggio of pure sines.
try writeCAF("chime", mix(
    tone(from: 659.26, duration: 0.9, amplitude: 0.28, decay: 3),
    delayed(tone(from: 830.61, duration: 0.78, amplitude: 0.26, decay: 3), by: 0.12),
    delayed(tone(from: 987.77, duration: 0.66, amplitude: 0.24, decay: 3), by: 0.24),
    delayed(tone(from: 1318.51, duration: 0.54, amplitude: 0.22, decay: 3), by: 0.36)), to: out)

// Abilities.
try writeCAF("slam", tone(from: 55, duration: 0.4, amplitude: 0.7, decay: 7), to: out)
try writeCAF("dash", { () -> [Float] in
    var rng = SeededRNG(seed: 0xDA54_2026)
    let count = seconds(0.3)
    return (0..<count).map { i in
        let t = Double(i) / Double(count)
        return Float(Double.random(in: -1...1, using: &rng) * 0.4 * t * exp(-2 * t))
    }
}(), to: out)
try writeCAF("split", mix(
    tone(from: 600, duration: 0.15, amplitude: 0.4, decay: 12),
    delayed(tone(from: 900, duration: 0.15, amplitude: 0.4, decay: 12), by: 0.06)), to: out)
try writeCAF("well", { () -> [Float] in
    let count = seconds(1.0)
    var phase = 0.0
    return (0..<count).map { i in
        let t = Double(i) / Double(count)
        let vibrato = 1 + 0.04 * sin(2 * .pi * 6 * t)
        phase += 2 * .pi * 65 * vibrato / sampleRate
        return Float(sin(phase) * 0.5 * (1 - t))
    }
}(), to: out)

// Misty's phase: an airy shimmer — three barely-detuned sines beating.
try writeCAF("phase", mix(
    tone(from: 1200, duration: 0.35, amplitude: 0.22, decay: 5),
    tone(from: 1207, duration: 0.35, amplitude: 0.22, decay: 5),
    tone(from: 1195, duration: 0.35, amplitude: 0.22, decay: 5)), to: out)

// Cloudfoam's boing: a springy downward sweep with an octave sparkle.
try writeCAF("boing", mix(
    tone(from: 180, to: 60, duration: 0.25, amplitude: 0.5, decay: 6),
    tone(from: 360, to: 120, duration: 0.2, amplitude: 0.15, decay: 8)), to: out)

// The ambience: a 16 s moonlit pad. Every component completes an integer
// number of cycles over the loop (frequencies are multiples of 1/16 Hz,
// LFO is exactly one cycle), so the loop point is mathematically seamless.
func makeAmbience() -> [Float] {
    let duration: Double = 16.0
    let count: Int = seconds(duration)
    let voices: [(hz: Double, amp: Double)] = [
        (110.0, 0.10), (110.0625, 0.10),   // A2 pair, ±1 cycle over the loop
        (164.8125, 0.08), (164.875, 0.08), // ~E3 pair
        (219.9375, 0.05),                  // ~A3
    ]
    var samples = [Float](repeating: 0, count: count)
    for i in 0..<count {
        let t: Double = Double(i) / sampleRate
        let lfo: Double = 0.75 + 0.25 * sin(2 * Double.pi * t / duration - Double.pi / 2)
        var sample: Double = 0
        for voice in voices {
            sample += sin(2 * Double.pi * voice.hz * t) * voice.amp
        }
        samples[i] = Float(sample * lfo * 0.55)
    }
    return samples
}
try writeCAF("ambience", makeAmbience(), to: out)

print("done")
