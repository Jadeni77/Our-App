import CoreMotion
import Observation
import SwiftUI

/// Gentle parallax from device tilt. Non-obvious bits: CMMotionManager must be
/// kept alive (it stops reporting if deallocated), updates are delivered on the
/// main queue so the @Observable write is safe, and start()/stop() bracket the
/// home's visibility so we never burn battery while a module is open.
/// On the simulator there's no motion hardware — offset just stays .zero.
@MainActor
@Observable
final class TiltModel {
    private let manager = CMMotionManager()
    private(set) var offset: CGSize = .zero

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let attitude = motion?.attitude else { return }
            // ±12pt max drift; roll/pitch are in radians, small angles ≈ linear.
            self?.offset = CGSize(
                width: max(-12, min(12, attitude.roll * 18)),
                height: max(-12, min(12, attitude.pitch * 18))
            )
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        offset = .zero
    }
}
